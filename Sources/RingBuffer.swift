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
  /// Default buffer size.  Unsigned so the compiler can check that the 
  /// capacity is greater than 0.
  public static let defaultCapacity: UInt = 4096

  /// Absolute maximum buffer size.  4 Terabytes ought to be enough...
  public static let absoluteMaximumCapacity: UInt = (1 << 42) - 1

  /// The length of the buffer
  public var count: Int {
    return Int(availableData)
  }

  /// The capacity of the buffer
  public let capacity: UInt

  /// The start position of the buffer
  public private(set) var start: UInt = 0

  /// The end position of the buffer
  public private(set) var end: UInt = 0

  /// The number (in bytes) of data that is available in this buffer
  public var availableData: UInt {
    // obo?
    return (end) % (capacity - start)
  }

  /// The number (in bytes) of space that is available in this buffer
  public var availableSpace: UInt {
    // obo?
    return capacity - end - 1
  }

  /// Returns true if the buffer is full
  public var isFull: Bool {
    return availableSpace == 0
  }

  /// Returns true if the buffer is empty, or if it contains 1 NULL byte
  public var isEmpty: Bool {
    return availableData == 0 || (availableData == 1 && elementPointer.pointee == 0)
  }

  /// The base address of the buffer
  public var elementPointer: UnsafeMutablePointer<UInt8> {
    return baseAddress.advanced(by: Int(start))
  }

  // MARK: - Private Properties

  /// The base address of the buffer.  This should not change
  private var baseAddress: UnsafeMutablePointer<UInt8>!

  /// The end address of the buffer
  private var endAddress: UnsafeMutablePointer<UInt8> {
    return baseAddress.advanced(by: Int(end))
  }

  /// The actual memory of the buffer
  private var storagePointer: UnsafeMutableRawPointer!
  
  /// A helper for finding the distance between our start address and end address
  private var distance: Int {
    return elementPointer.distance(to: endAddress)
  }

  /// The DispatchQueue that will synchronize access to the buffer
  private let dispatchQueue: DispatchQueue

  // MARK: - Initializers

  /// Create a new ring buffer with a given capacity
  ///
  /// - parameter capacity: The capacity of the new buffer, in bytes
  public init(capacity: UInt = RingBuffer.defaultCapacity) {
    self.capacity = roundUpCapacity(capacity) + 1

    self.dispatchQueue = DispatchQueue(label: "ring-buffer.serial-queue")

    self.storagePointer = UnsafeMutableRawPointer.allocate(
      bytes: Int(self.capacity), alignedTo: MemoryLayout<UInt8>.alignment
    )

    self.baseAddress = self.storagePointer.initializeMemory(
      as: UInt8.self, at: 0, count: Int(self.capacity), to: 0
    )
  }

  /// Clean up our allocated memory when we are deinitialized
  deinit {
    self.baseAddress.deinitialize(count: Int(self.capacity))
    self.storagePointer.deallocate(
      bytes: Int(self.capacity), alignedTo: MemoryLayout<UInt8>.alignment
    )
  }

  // MARK: - Public Functions

  /// Append a byte to the ring buffer
  ///
  /// - parameter byte: The byte to add to the buffer
  /// - note: This will silently fail if an error occurs.  
  ///   To raise the error, use one of the `write()` methods.
  public func append(_ byte: UInt8) {
    // mutable copy of `byte`
    var theByte = byte

    withUnsafePointer(to: &theByte, { [unowned self] (bytePointer) in
      _ = try? self.write(from: bytePointer, count: 1)
    })
  }

  /// Append a sequence of bytes to the ring buffer
  ///
  /// - parameter bytes: The sequence of bytes to add to the buffer
  /// - precondition: MemoryLayout<S.Iterator.Element>.size == MemoryLayout<UInt8>.size
  /// - note: This will silently fail if an error occurs.
  ///   To raise the error, use one of the `write()` methods.
  public func append(contentsOf bytes: ContiguousArray<UInt8>) {
    bytes.withUnsafeBufferPointer { [unowned self] (bufferPointer: UnsafeBufferPointer<UInt8>) in
      _ = try? self.write(from: bufferPointer)
    }
  }

  /// Append a sequence of bytes to the ring buffer
  ///
  /// - parameter bytes: The sequence of bytes to add to the buffer
  /// - precondition: MemoryLayout<S.Iterator.Element>.size == MemoryLayout<UInt8>.size
  /// - note: This will silently fail if an error occurs.
  ///   To raise the error, use one of the `write()` methods.
  public func append(contentsOf bytes: ContiguousArray<Int8>) {
    bytes.withUnsafeBufferPointer { [unowned self] (pointerA: UnsafeBufferPointer<Int8>) in
      pointerA.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: pointerA.count, { pointerB in
        _ = try? self.write(from: pointerB, count: pointerA.count)
      })
    }
  }

  public func append<S: Sequence>(contentsOf: S) where S.Iterator.Element == UInt8 {
    for byte in contentsOf {
      self.append(byte)
    }
  }

  /// Append the contents of a `Data` structure to the buffer
  ///
  /// - parameter data: The data structure to append to the buffer
  /// - note: This will silently fail if an error occurs.
  ///   To raise the error, use one of the `write()` methods.
  public func append(data: Data) {
    _ = try? self.write(from: data)
  }
  
  /// Write into the buffer, given pointer data and length
  ///
  /// - parameter from: The bytes to write into the buffer
  /// - parameter length: The number of bytes to write into the buffer
  /// - precondition: `count >= 0`
  /// - throws: RingBufferError if an error was encountered
  /// - returns: The number of bytes read
  @discardableResult
  public func write(from bytes: UnsafePointer<UInt8>, count: Int) throws -> Int {
    // can't write fewer than 0 bytes
    precondition(count >= 0, "You can't write 0 bytes to the buffer, son!")

    let count = UInt(count)

    // reset the buffer if we have no available data
    if availableData == 0 { reset() }

    // bail if we don't have enough space
    guard count <= self.availableSpace else {
      throw RingBufferError.insufficientSpace(requested: count, available: availableSpace)
    }

    self.dispatchQueue.sync {
      self.endAddress.assign(from: bytes, count: Int(count))
      commitWrite(count: count)
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
  public func write(from buffer: UnsafeBufferPointer<UInt8>) throws -> Int {
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
      return try cstring.withMemoryRebound(to: UInt8.self, capacity: strlen) { [unowned self] in
        return try self.write(from: $0, count: strlen)
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
  /// - precondition: `count` is greater than 0, and less than `availableData`
  /// - throws: RingBufferError if an error was encountered
  /// - returns: The number of bytes read
  @discardableResult
  public func read(into data: inout Data, count: Int) throws -> Int {
    let count = UInt(count)
    guard count <= availableData else {
      throw RingBufferError.insufficientData(requested: count, available: availableData)
    }

    let buffer: UnsafeBufferPointer<UInt8> = getUnsafeBufferPointer(count: self.distance)

    data.append(buffer)
    
    commitRead(count: count)

    if self.end == self.start {
      reset()
    }

    return Int(count)
  }

  /// Get a string from the buffer 
  /// 
  /// - parameter amount: The number of bytes to read
  /// - precondition: `amount` is greater than 0
  public func gets(_ amount: UInt) throws -> String {
    precondition(amount > 0, "`amount` must be greater than 0!")

    guard amount <= availableData else {
      throw RingBufferError.insufficientData(requested: amount, available: availableData)
    }

    let buffer: UnsafeBufferPointer<UInt8> = getUnsafeBufferPointer(count: Int(amount))

    guard let result = String(bytes: buffer, encoding: .utf8),
              UInt(result.lengthOfBytes(using: .utf8)) == amount else {
      throw RingBufferError.conversionError
    }

    commitRead(count: amount)

    guard availableData >= 0 else {
      throw RingBufferError.internal("Error occured while commiting the read to the buffer")
    }

    if self.start == self.end {
      reset()
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
    _ body: (UnsafeBufferPointer<UInt8>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(getUnsafeBufferPointer(count: self.distance))
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
    _ body: (UnsafeMutableBufferPointer<UInt8>) throws -> R
  ) rethrows -> R {
    defer { _fixLifetime(self) }
    return try body(UnsafeMutableBufferPointer(start: self.elementPointer, count: self.distance))
  }

  /// Access the bytes in the data.
  ///
  /// - warning: The byte pointer argument should not be stored and used
  ///   outside of the lifetime of the call to the closure.
  public func withUnsafeBytes<ResultType>(
    _ body: (UnsafePointer<UInt8>) throws -> ResultType
  ) rethrows -> ResultType {
    defer { _fixLifetime(self) }
    return try body(UnsafePointer(self.elementPointer))
  }

  // MARK: - Private Functions

  /// Commit a write into the buffer, moving the `start` position
  private func commitRead(count: UInt) {
    self.start = (self.start + count) % self.capacity
  }

  /// Commit a write into the buffer, moving the `end` position
  private func commitWrite(count: UInt) {
    self.end = (self.end + count) % self.capacity
  }

  /// Get an UnsafeBufferPointer to the storage of the RingBuffer
  private func getUnsafeBufferPointer<T>(count: Int) -> UnsafeBufferPointer<T> {
    return self.elementPointer.withMemoryRebound(to: T.self, capacity: count, { newStart in
      return UnsafeBufferPointer(start: newStart, count: count)
    })
  }

  /// Reset the buffer
  func reset() {
    self.start = 0
    self.end = 0
  }
}


// MARK: - Custom{,Debug}StringConvertible

extension RingBuffer: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
  /// A human-readable description of the data
  public var description: String {
    return "\(self.count) bytes"
  }

  /// A human-readable debug description of the data
  public var debugDescription: String {
    return description
  }

  public var customMirror: Mirror {
    let byteCount = self.count
    var children: [(label: String?, value: Any)] = []
    children.append((label: "count", value: byteCount))

    self.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
      children.append((label: "pointer", value: bytes))
    }

    //    if byteCount < 64 {
    //      children.append((label: "bytes", value: self[0..<byteCount].map { $0 }))
    //    }

    let m = Mirror(self, children: children, displayStyle: Mirror.DisplayStyle.struct)
    return m
  }
}

// MARK: - Deprecated Methods

extension RingBuffer {
  @available(*, unavailable, renamed: "count")
  public var length: Int {
    get { fatalError() }
    set { fatalError() }
  }

  @available(*, unavailable, renamed: "baseAddress")
  fileprivate var _ptr: UnsafeMutablePointer<UInt8> {
    fatalError()
  }
}

// MARK: - Implementation Helpers

fileprivate let CHUNK_SIZE:     UInt = 1 << 29
fileprivate let LOW_THRESHOLD:  UInt = 1 << 20
fileprivate let HIGH_THRESHOLD: UInt = 1 << 32

@inline(__always)
fileprivate func roundUpCapacity(_ capacity: UInt) -> UInt {
  let result: UInt

  if capacity < 16 {
    result = 16
  } else if capacity < LOW_THRESHOLD {
    /* up to 4x */
    let idx = flsl(Int(capacity))
    let power = idx + ((idx % 2 == 0) ? 0 : 1)
    result = 1 << UInt(power)
  } else if capacity < HIGH_THRESHOLD {
    /* up to 2x */
    result = 1 << UInt(flsl(Int(capacity)))
  } else {
    /* Round up to the nearest multiple of `CHUNK_SIZE` */
    let newCapa = CHUNK_SIZE * (1 + (capacity >> UInt(flsl(Int(CHUNK_SIZE)) - 1)))
    result = min(newCapa, RingBuffer.absoluteMaximumCapacity)
  }

  return result
}
