//
//  RingBuffer.swift
//  RingBuffer
//
//  Created by Morgan Lieberthal on 10/10/16.
//
//

import Foundation
import Dispatch

// MARK: RingBuffer

/// An implementation of a Circular Buffer.
///
/// The ring buffer is agnostic about the data type it stores, and deals
/// directly with bytes.
///
/// - note: The buffer internally rounds up `capacity` to the nearest page size. 
///   To determine the actual capacity of the buffer, check the return value of `capacity`
///   after initialization.
///
/// - note: This class is thread-safe.
///
/// - seealso: [Circular Buffer on Wikipedia](https://en.wikipedia.org/wiki/Circular_buffer)
public struct RingBuffer {
  /// Default buffer size.
  public static let defaultCapacity: Int = 4096

  // MARK: - Public Properties 

  /// The capacity of the buffer
  public var capacity: Int {
    return _storage.capacity
  }

  /// The number of bytes currently stored in the buffer
  public var count: Int {
    return availableData
  }

  /// The start position of the buffer
  public private(set) var start: Int = 0

  /// The end position of the buffer
  public private(set) var end: Int = 0

  /// The number (in bytes) of data that is available in this buffer
  public var availableData: Int {
    // obo?
    return (end) % (capacity - start)
  }

  /// The number (in bytes) of space that is available in this buffer
  public var availableSpace: Int {
    // obo?
    return capacity - end - 1
  }

  /// Returns true if the buffer is full
  public var isFull: Bool {
    return availableSpace == 0
  }

  /// Returns true if the buffer is empty, or if it contains 1 NULL byte
  public var isEmpty: Bool {
    return availableData == 0
  }

  /// The base address of the buffer
  public var elementPointer: UnsafeMutablePointer<UInt8> {
    return baseAddress.advanced(by: Int(start))
  }

  // MARK: - Private Properties

  /// The base address of the buffer.
  private var baseAddress: UnsafeMutablePointer<UInt8>! {
    return _storage.baseAddress!
  }

  /// The end address of the buffer
  private var endAddress: UnsafeMutablePointer<UInt8> {
    return baseAddress.advanced(by: Int(end))
  }

  /// A helper for finding the distance between our start address and end address
  private var distance: Int {
    return elementPointer.distance(to: endAddress)
  }

  /// The DispatchQueue that will synchronize access to the buffer
  private let dispatchQueue: DispatchQueue

  /// The backing storage class
  private var _storage: RingBufferStorage

  // MARK: - Initializers

  /// Create a new ring buffer with a given capacity
  ///
  /// - parameter capacity: The capacity of the new buffer, in bytes
  public init(capacity: Int = RingBuffer.defaultCapacity) {
    self.dispatchQueue = DispatchQueue(label: "ring-buffer.serial-queue")
    self._storage = RingBufferStorage(capacity: capacity)
  }

  // MARK: - Public Functions

  /// Append bytes to the buffer.
  ///
  /// - parameter bytes: A pointer to the bytes to copy into the data.
  /// - parameter count: The number of bytes to copy.
  ///
  /// - precondition: `count > 0 && count <= self.availableSpace`
  ///
  /// - warning: This method does not do any bounds checking, so be sure that
  ///   `count` does not exceed `availableSpace`
  public mutating func append(_ bytes: UnsafeRawPointer, count: Int) {
    precondition(count > 0)
    if availableData == 0 { reset() }
    precondition(count <= availableSpace, "Not enough space in the buffer")

    let bytePointer = bytes.bindMemory(to: UInt8.self, capacity: count)

    self.dispatchQueue.sync {
      self.endAddress.assign(from: bytePointer, count: count)
      self.commitWrite(count: count)
    }
  }
  
  /// Append a buffer to the buffer.
  ///
  /// - parameter buffer: The buffer of bytes to append.  The size is calculated
  ///   from `SourceType` and `buffer.count`.
  ///
  /// - precondition: `buffer.count <= self.availableSpace`
  ///
  /// - warning: This method does not do any bounds checking, so be sure that
  ///   `buffer.count` does not exceed `self.availableSpace`
  public mutating func append<SourceType>(_ buffer: UnsafeBufferPointer<SourceType>) {
    self.append(buffer.baseAddress!, count: buffer.count * MemoryLayout<SourceType>.stride)
  }

  /// Append a sequence of bytes to the ring buffer.
  ///
  /// - parameter contiguous: The sequence of bytes to add to the buffer.  Internally,
  ///   this method calls `append<T>(_:UnsafeBufferPointer<T>)`.
  ///
  /// - precondition: `count > 0 && count <= self.availableSpace`
  ///
  /// - warning: This method does not do any bounds checking, so be sure that
  ///   `contigous.count` does not exceed `self.availableSpace`
  public mutating func append<SourceType>(contentsOf contiguous: ContiguousArray<SourceType>) {
    contiguous.withUnsafeBufferPointer { bufferPointer in
      self.append(bufferPointer)
    }
  }

  /// Append the contents of a `Data` structure to the buffer
  ///
  /// - parameter data: The data structure to append to the buffer
  ///
  /// - warning: This method does not do any bounds checking, so be sure that
  ///   `data.count` does not exceed `self.availableSpace`
  public mutating func append(_ data: Data) {
    data.withUnsafeBytes { (dataPointer: UnsafePointer<UInt8>) in
      self.append(dataPointer, count: data.count)
    }
  }
  
  /// Write into the buffer, given pointer data and length
  ///
  /// - parameter from: The bytes to write into the buffer
  /// - parameter count: The number of bytes to write into the buffer
  /// - precondition: `count > 0`
  /// - throws: RingBufferError if an error was encountered
  /// - returns: The number of bytes read
  @discardableResult
  public mutating func write(from bytes: UnsafePointer<UInt8>, count: Int) throws -> Int {
    // can't write fewer than 0 bytes
    precondition(count >= 0, "You can't write 0 bytes to the buffer, son!")

    // reset the buffer if we have no available data
    if availableData == 0 { reset() }

    // bail if we don't have enough space
    guard count <= self.availableSpace else {
      throw RingBufferError.insufficientSpace(requested: count, available: availableSpace)
    }

    self.dispatchQueue.sync {
      self.endAddress.assign(from: bytes, count: Int(count))
      self.commitWrite(count: count)
    }

    return Int(count)
  }

  /// Write into the buffer, given pointer data and length
  ///
  /// - parameter from: The bytes to write into the buffer
  /// - parameter length: The number of bytes to write into the buffer
  /// - throws: RingBufferError if an error was encountered
  /// - returns: The number of bytes written into the buffer
  @discardableResult
  public mutating func write(from buffer: UnsafeBufferPointer<UInt8>) throws -> Int {
    return try write(from: buffer.baseAddress!, count: buffer.count)
  }

  /// Write the contents of a string to the buffer
  ///
  /// - parameter string: The string to write to the buffer
  /// - throws: A RingBufferError if an error occured
  /// - returns: The number of bytes written to the buffer
  @discardableResult
  public mutating func write(string: String) throws -> Int {
    let strlen = string.lengthOfBytes(using: .utf8)
    return try string.withCString { cstring in
      return try cstring.withMemoryRebound(to: UInt8.self, capacity: strlen) {
        return try write(from: $0, count: strlen)
      }
    }
  }

  /// Write the contents of a `Data` object to the buffer
  ///
  /// - parameter from: The `Data` object that contains the data to write
  /// - throws: RingBufferError if an error occurs
  /// - returns: the number of bytes written
  @discardableResult
  public mutating func write(from data: Data) throws -> Int {
    return try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) -> Int in
      return try write(from: pointer, count: data.count)
    }
  }

  /// Read `count` bytes from the buffer, into `into`
  ///
  /// - parameter into: A `Data` struct to write data into
  /// - parameter count: The number of bytes to read
  /// - precondition: `count` is greater than 0, and less than `availableData`
  /// - throws: RingBufferError if an error was encountered
  /// - returns: The number of bytes read
  @discardableResult
  public mutating func read(into data: inout Data, count: Int) throws -> Int {
    guard count <= availableData else {
      throw RingBufferError.insufficientData(requested: count, available: availableData)
    }

    return dispatchQueue.sync(execute: {
      let buffer = UnsafeBufferPointer<UInt8>(start: self.elementPointer, count: self.distance)

      data.append(buffer)

      self.commitRead(count: count)
      
      if self.end == self.start {
        self.reset()
      }
      
      return Int(count)
    })
  }

  /// Get a string from the buffer 
  /// 
  /// - parameter amount: The number of bytes to read
  /// - precondition: `amount` is greater than 0
  public mutating func gets(_ amount: Int) throws -> String {
    precondition(amount > 0, "`amount` must be greater than 0!")

    guard amount <= availableData else {
      throw RingBufferError.insufficientData(requested: amount, available: availableData)
    }

    return try dispatchQueue.sync(execute: {
      let buffer = UnsafeBufferPointer<UInt8>(start: self.elementPointer, count: amount)

      
      guard let result = String(bytes: buffer, encoding: .utf8),
                result.lengthOfBytes(using: .utf8) == amount else {
                  throw RingBufferError.conversionError
      }

      self.commitRead(count: amount)
      
      guard self.availableData >= 0 else {
        throw RingBufferError.internal("Error occured while commiting the read to the buffer")
      }
      
      if self.start == self.end {
        self.reset()
      }
      
      return result
    })
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
  public func withUnsafeBufferPointer<ContentType, ResultType>(
    _ body: (UnsafeBufferPointer<ContentType>) throws -> ResultType
  ) rethrows -> ResultType {
    defer { _fixLifetime(self) }
    return try _storage.withUnsafeBufferPointer(body)
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
  public func withUnsafeMutableBufferPointer<ContentType, ResultType>(
    _ body: (UnsafeMutableBufferPointer<ContentType>) throws -> ResultType
  ) rethrows -> ResultType {
    defer { _fixLifetime(self) }
    return try _storage.withUnsafeMutableBufferPointer(body)
  }

  /// Access the bytes in the data.
  ///
  /// - warning: The byte pointer argument should not be stored and used
  ///   outside of the lifetime of the call to the closure.
  public func withUnsafeBytes<ContentType, ResultType>(
    _ body: (UnsafePointer<ContentType>) throws -> ResultType
  ) rethrows -> ResultType {
    defer { _fixLifetime(self) }
    return try _storage.withUnsafeBytes(body)
  }

  /// Clear the buffer of any stored data
  ///
  /// - parameter upTo: The number of bytes to clear from the buffer.  Defaults to all of it.
  public mutating func clear(upTo: Int? = nil) {
    dispatchQueue.sync {
      self.commitRead(count: upTo ?? self.availableData)
    }
  }

  // MARK: - Private Functions

  /// Commit a write into the buffer, moving the `start` position
  private mutating func commitRead(count: Int) {
    self.start = (self.start + count) % self.capacity
    if self.start == self.end {
      self.reset()
    }
  }

  /// Commit a write into the buffer, moving the `end` position
  private mutating func commitWrite(count: Int) {
    self.end = (self.end + count) % self.capacity
  }

  /// Reset the buffer
  private mutating func reset() {
    self.start = 0
    self.end = 0
  }
}


// MARK: - Custom{,Debug}StringConvertible

extension RingBuffer: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
  /// A human-readable description of the data
  public var description: String {
    return "\(self.availableData) bytes"
  }

  /// A human-readable debug description of the data
  public var debugDescription: String {
    return description
  }

  public var customMirror: Mirror {
    let byteCount = self.availableData
    var children: [(label: String?, value: Any)] = []
    children.append((label: "count", value: byteCount))

    self.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
      children.append((label: "pointer", value: bytes))
    }

    let m = Mirror(self, children: children, displayStyle: Mirror.DisplayStyle.struct)
    return m
  }
}
