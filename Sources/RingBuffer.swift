//
//  RingBuffer.swift
//  RingBuffer
//
//  Created by Morgan Lieberthal on 10/10/16.
//
//

import Foundation
import Dispatch

/// An implementation of a Circular Buffer.
///
/// The ring buffer is agnostic about the data type it stores, and deals
/// directly with bytes.
///
/// - note: This class is thread-safe.
///
/// - seealso: [Circular Buffer on Wikipedia](https://en.wikipedia.org/wiki/Circular_buffer)
public final class RingBuffer {
  // MARK: - Public Properties
  public typealias Byte = UInt8

  /// The length of the buffer
  public let count: Int

  /// The start position of the buffer
  public var start: Int = 0

  /// The end position of the buffer
  public var end: Int = 0

  /// The length of the buffer
  public var length: Int {
    return count
  }

  /// The number (in bytes) of data that is available in this buffer
  public var availableData: Int {
    // obo?
    return (end) % (count - start)
  }

  /// The number (in bytes) of space that is available in this buffer
  public var availableSpace: Int {
    // obo?
    return count - end - 1
  }

  /// Returns true if the buffer is full
  public var isFull: Bool {
    return availableSpace == 0
  }

  /// Returns true if the buffer is empty
  public var isEmpty: Bool {
    return availableData == 0
  }

  /// The start address of the buffer
  public var startAddress: UnsafeMutablePointer<Byte> {
    return _ptr.advanced(by: start)
  }

  /// The end address of the buffer
  public var endAddress: UnsafeMutablePointer<Byte> {
    return _ptr.advanced(by: end)
  }

  // MARK: - Private Properties

  /// The actual memory of the buffer
  private var _ptr: UnsafeMutablePointer<Byte>

  /// A helper for finding the distance between our start address and end address
  private var distance: Int {
    return startAddress.distance(to: endAddress)
  }

  /// The DispatchQueue that will synchronize access to the buffer
  private let dispatchQueue: DispatchQueue

  // MARK: - Initializers

  /// Create a new ring buffer with a given capacity
  ///
  /// - parameter capacity: The capacity of the new buffer, in bytes
  public init(capacity: Int) {
    self.count = capacity + 1 // to account for null terminator

    self.dispatchQueue = DispatchQueue(label: "ring-buffer.serial-queue")

    self._ptr  = UnsafeMutablePointer.allocate(capacity: capacity + 1)
    self._ptr.initialize(to: 0, count: capacity + 1)
  }

  /// Clean up our allocated memory when we are deinitialized
  deinit {
    self._ptr.deinitialize(count: self.length)
    self._ptr.deallocate(capacity: self.length)
  }

  // MARK: - Public Functions

  /// Write into the buffer, given pointer data and length
  ///
  /// - parameter from: The bytes to write into the buffer
  /// - parameter length: The number of bytes to write into the buffer
  /// - throws: RingBufferError if an error was encountered
  /// - returns: The number of bytes read
  @discardableResult
  public func write(from bytes: UnsafePointer<Byte>, count: Int) throws -> Int {
    // reset the buffer if we have no available data
    if availableData == 0 { reset() }

    // bail if we don't have enough space
    guard count <= self.availableSpace else {
      throw RingBufferError.insufficientSpace(requested: count, available: availableSpace)
    }

    self.dispatchQueue.sync {
      self.endAddress.assign(from: bytes, count: count)
      commitWrite(count: count)
    }

    return count
  }

  /// Write into the buffer, given pointer data and length
  ///
  /// - parameter from: The bytes to write into the buffer
  /// - parameter length: The number of bytes to write into the buffer
  /// - throws: RingBufferError if an error was encountered
  /// - returns: The number of bytes written into the buffer
  @discardableResult
  public func write(from buffer: UnsafeBufferPointer<Byte>) throws -> Int {
    return try write(from: buffer.baseAddress!, count: buffer.count)
  }

  /// Write the contents of a string to the buffer
  ///
  /// - parameter string: The string to write to the buffer
  /// - throws: A RingBufferError if an error occured
  /// - returns: The number of bytes written to the buffer
  @discardableResult
  public func write(string: String) throws -> Int {
    let strlen = string.lengthOfBytes(using: .utf8)
    return try string.withCString { [unowned self] (cstring) in
      return try cstring.withMemoryRebound(to: UInt8.self, capacity: strlen) { [unowned self] (buffer) in
        return try self.write(from: buffer, count: strlen)
      }
    }
  }

  /// Write the contents of a `Data` object to the buffer
  ///
  /// - parameter from: The `Data` object that contains the data to write
  /// - throws: RingBufferError if an error occurs
  /// - returns: the number of bytes written
  @discardableResult
  public func write(from data: Data) throws -> Int {
    return try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) -> Int in
      return try write(from: pointer, count: data.count)
    }
  }

  /// Read `count` bytes from the buffer, into `into`
  ///
  /// - parameter into: A `Data` struct to write data into
  /// - parameter count: The number of bytes to read
  /// - throws: RingBufferError if an error was encountered
  /// - returns: The number of bytes read
  @discardableResult
  public func read(into data: inout Data, count: Int) throws -> Int {
    guard count <= availableData else {
      throw RingBufferError.insufficientData(requested: count, available: availableData)
    }

    let buffer = UnsafeBufferPointer(start: self.startAddress, count: distance)

    data.append(buffer)
    
    commitRead(count: count)

    if self.end == self.start {
      reset()
    }

    return count
  }

  /// Get a string from the buffer 
  /// 
  /// - parameter amount: The number of bytes to read
  public func gets(_ amount: Int) throws -> String {
    guard amount > 0 else {
      throw RingBufferError.invalidArgument("`amount` must be greater than 0, not `\(amount)`")
    }

    guard amount <= availableData else {
      throw RingBufferError.insufficientData(requested: amount, available: availableData)
    }

    let buffer = UnsafeBufferPointer(start: self.startAddress, count: amount)

    guard let result = String(bytes: buffer, encoding: .utf8),
              result.lengthOfBytes(using: .utf8) == amount else {
      throw RingBufferError.conversionError
    }

    commitRead(count: amount)

    guard availableData >= 0 else {
      throw RingBufferError.internal("Error occured while commiting the read to the buffer")
    }

    return result
  }

  /// Calls a closure with a pointer to the buffer's contiguous storage.
  ///
  /// Often, the optimizer can eliminate bounds checks within an array
  /// algorithm, but when that fails, invoking the same algorithm on the
  /// buffer pointer passed into your closure lets you trade safety for speed.
  ///
  /// The following example shows how you can iterate over the contents of the
  /// buffer pointer:
  ///
  ///     let numbers = [1, 2, 3, 4, 5]
  ///     let sum = numbers.withUnsafeBufferPointer { buffer -> Int in
  ///         var result = 0
  ///         for i in stride(from: buffer.startIndex, to: buffer.endIndex, by: 2) {
  ///             result += buffer[i]
  ///         }
  ///         return result
  ///     }
  ///     // 'sum' == 9
  ///
  /// - parameter body: A closure with an `UnsafeBufferPointer` parameter that
  ///   points to the contiguous storage for the array. If `body` has a return
  ///   value, it is used as the return value for the
  ///   `withUnsafeBufferPointer(_:)` method. The pointer argument is valid
  ///   only for the duration of the closure's execution.
  ///
  /// - returns: The return value of the `body` closure parameter, if any.
  ///
  /// - seealso: `withUnsafeMutableBufferPointer`, `UnsafeBufferPointer`
  public func withUnsafeBufferPointer<R>(
    _ body: (UnsafeBufferPointer<Byte>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(UnsafeBufferPointer(start: self.startAddress, count: self.distance))
  }

  /// Calls the given closure with a pointer to the buffer's mutable contiguous
  ///
  /// Often, the optimizer can eliminate bounds checks within an array
  /// algorithm, but when that fails, invoking the same algorithm on the
  /// buffer pointer passed into your closure lets you trade safety for speed.
  ///
  /// The following example shows modifying the contents of the
  /// `UnsafeMutableBufferPointer` argument to `body` alters the contents of
  /// the array:
  ///
  ///     var numbers = [1, 2, 3, 4, 5]
  ///     numbers.withUnsafeMutableBufferPointer { buffer in
  ///         for i in stride(from: buffer.startIndex, to: buffer.endIndex - 1, by: 2) {
  ///             swap(&buffer[i], &buffer[i + 1])
  ///         }
  ///     }
  ///     print(numbers)
  ///     // Prints "[2, 1, 4, 3, 5]"
  ///
  /// - warning: Do not rely on anything about `self` (the buffer that is the
  ///   target of this method) during the execution of the `body` closure: It
  ///   may not appear to have its correct value.  Instead, use only the
  ///   `UnsafeMutableBufferPointer` argument to `body`.
  ///
  /// - parameter body: A closure with an `UnsafeMutableBufferPointer`
  ///   parameter that points to the contiguous storage for the buffer. If
  ///   `body` has a return value, it is used as the return value for the
  ///   `withUnsafeMutableBufferPointer(_:)` method. The pointer argument is
  ///   valid only for the duration of the closure's execution.
  /// - returns: The return value of the `body` closure parameter, if any.
  ///
  /// - seealso: `withUnsafeBufferPointer`, `UnsafeMutableBufferPointer`
  public func withUnsafeMutableBufferPointer<R>(
    _ body: (UnsafeMutableBufferPointer<Byte>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(UnsafeMutableBufferPointer(start: self.startAddress, count: self.distance))
  }

  // MARK: - Private Functions

  /// Commit a write into the buffer, moving the `start` position
  private func commitRead(count: Int) {
    self.start = (self.start + count) % self.length
  }

  /// Commit a write into the buffer, moving the `end` position
  private func commitWrite(count: Int) {
    self.end = (self.end + count) % self.length
  }

  /// Reset the buffer
  func reset() {
    self.start = 0
    self.end = 0
  }
}
