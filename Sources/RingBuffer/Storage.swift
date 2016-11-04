//
//  Storage.swift
//  RingBuffer
//
//  Created by Morgan Lieberthal on 11/3/16.
//
//

import Libc

/// Storage for `RingBuffer`
final class RingBufferStorage {
  /// Capacity of this storage instance, in bytes
  let capacity: Int

  /// Pointer to our allocated memory
  var storagePointer: UnsafeMutableRawPointer!

  /// Base address of the storage, as mapped to UInt8
  var baseAddress: UnsafeMutablePointer<UInt8>?

  /// Create an instance of `RingBufferStorage`, with a given `capacity`, using `allocator` to
  /// allocate the memory.
  ///
  /// - parameter capacity: The capacity of the storage to allocate
  ///
  /// - note: `capacity` is rounded up to the nearest page size.
  ///   To determine the actual capacity of the buffer, check the return value
  ///   of `capacity`.
  init(capacity: Int) {
    self.capacity = roundUpCapacity(capacity) + 1

    self.storagePointer = UnsafeMutableRawPointer.allocate(
      bytes: self.capacity, alignedTo: MemoryLayout<UInt8>.alignment
    )

    self.baseAddress = self.storagePointer.initializeMemory(
      as: UInt8.self, at: 0, count: self.capacity, to: 0
    )
  }

  /// Deallocate our storage, if it exists, upon deinitialization
  deinit {
    deallocate()
    _fixLifetime(self)
  }

  // MARK: - withUnsafe...

  /// Calls a closure with a pointer to the buffer's contiguous storage.
  ///
  /// The UnsafeBufferPointer passed to the block will begin at the start address
  /// and continue for the entire capacity of the storage, even if the elements are
  /// nil.
  ///
  /// - parameter body: A closure with an `UnsafeBufferPointer` parameter that
  ///   points to the contiguous storage.  If `body` has a return value,
  ///   it is used as the return value for the
  ///   `withUnsafeBufferPointer(_:)` method.  The pointer argument is valid
  ///   only for the duration of the closure's execution.
  ///
  /// - returns: The return value of the `body` closure parameter, if any.
  ///
  /// - seealso: `withUnsafeMutableBufferPointer`, `UnsafeBufferPointer`
  func withUnsafeBufferPointer<ContentType, ResultType>(
    _ body: (UnsafeBufferPointer<ContentType>) throws -> ResultType
  ) rethrows -> ResultType {
    let bytes = _getUnsafeBytesPointer()
    defer { _fixLifetime(self) }

    let capa = self.capacity / MemoryLayout<ContentType>.stride
    let startPointer = bytes.bindMemory(to: ContentType.self, capacity: capa)
    let bufPointer = UnsafeBufferPointer(start: startPointer, count: capa)

    return try body(bufPointer)
  }

  /// Calls a closure with a pointer to the buffer's mutable contiguous storage.
  ///
  /// The UnsafeBufferPointer passed to the block will begin at the start address
  /// and continue for the entire capacity of the storage, even if the elements are
  /// nil.
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
  ///
  /// - returns: The return value of the `body` closure parameter, if any.
  ///
  /// - seealso: `withUnsafeBufferPointer`, `UnsafeMutableBufferPointer`,
  ///   `withUnsafeBytes`, `withUnsafeMutableBytes`
  func withUnsafeMutableBufferPointer<ContentType, ResultType>(
    _ body: (UnsafeMutableBufferPointer<ContentType>) throws -> ResultType
  ) rethrows -> ResultType {
    let mutableBytes = _getUnsafeMutableBytesPointer()
    defer { _fixLifetime(self) }

    let bufCapa = self.capacity / MemoryLayout<ContentType>.stride
    let startPtr = mutableBytes.bindMemory(to: ContentType.self, capacity: bufCapa)

    let bufPtr = UnsafeMutableBufferPointer(start: startPtr, count: bufCapa)

    return try body(bufPtr)
  }

  /// Access the bytes in the data.
  ///
  /// - warning: The byte pointer argument should not be stored and used
  ///   outside of the lifetime of the call to the closure.
  func withUnsafeBytes<ContentType, ResultType>(
    _ body: (UnsafePointer<ContentType>) throws -> ResultType
  ) rethrows -> ResultType {
    let bytes = _getUnsafeBytesPointer()
    defer { _fixLifetime(self) }

    let contentPointer = bytes.bindMemory(
      to: ContentType.self, capacity: self.capacity / MemoryLayout<ContentType>.stride
    )

    return try body(contentPointer)
  }

  /// Mutate the bytes in the data.
  ///
  /// This function assumes that you are mutating the contents.
  /// - warning: The byte pointer argument should not be stored and used 
  ///   outside of the lifetime of the call to the closure.
  func withUnsafeMutableBytes<ContentType, ResultType>(
    _ body: (UnsafeMutablePointer<ContentType>) throws -> ResultType
  ) rethrows -> ResultType {
    let mutableBytes = _getUnsafeMutableBytesPointer()
    defer { _fixLifetime(self) }

    let contentPointer = mutableBytes.bindMemory(
      to: ContentType.self, capacity: self.capacity / MemoryLayout<ContentType>.stride
    )

    return try body(contentPointer)
  }

  // MARK: - Private Methods

  /// Return a pointer to the bytes of the storage
  private func _getUnsafeBytesPointer() -> UnsafeRawPointer {
    return UnsafeRawPointer(self.storagePointer)
  }

  /// Return a pointer to the mutable bytes of the storage
  private func _getUnsafeMutableBytesPointer() -> UnsafeMutableRawPointer {
    return UnsafeMutableRawPointer(self.storagePointer)
  }

  /// Deallocate the storage memory, deinitializing if it is already initialized
  private func deallocate() {
    if let baseAddress = self.baseAddress {
      baseAddress.deinitialize(count: self.capacity)
    }

    self.storagePointer.deallocate(bytes: self.capacity, alignedTo: MemoryLayout<UInt8>.alignment)
  }
}

// MARK: - Implementation Helpers

#if arch(x86_64) || arch(arm64) // we are on a 64-bit system
  /// Absolute maximum buffer size: 4 TB on 64-bit.
  fileprivate let RINGBUFFER_MAX_SIZE: Int = (1 << 42) - 1

  /// Chunk size of our memory allocations
  fileprivate let CHUNK_SIZE:     Int = 1 << 29

  /// Low threshold of memory allocation
  fileprivate let LOW_THRESHOLD:  Int = 1 << 20

  /// High threshold of memory allocation
  fileprivate let HIGH_THRESHOLD: Int = 1 << 32

#elseif arch(arm) || arch(i386) // we are on a 32-bit system
  /// Absolute maximum buffer size: 2 GB on 32-bit.
  fileprivate let RINGBUFFER_MAX_SIZE: Int = (1 << 31) - 1

  /// Chunk size of our memory allocations
  fileprivate let CHUNK_SIZE:     Int = 1 << 26
  
  /// Low threshold of memory allocation
  fileprivate let LOW_THRESHOLD:  Int = 1 << 20
  
  /// High threshold of memory allocation
  fileprivate let HIGH_THRESHOLD: Int = 1 << 29
#endif

@inline(__always)
fileprivate func roundUpCapacity(_ capacity: Int) -> Int {
  let result: Int

  if capacity < 16 {
    result = 16
  } else if capacity < LOW_THRESHOLD {
    // up to 4x
    let idx = flsl(capacity)
    // make sure we shift by a multiple of 2
    result = 1 << Int(idx + ((idx % 2 == 0) ? 0 : 1))
  } else if capacity < HIGH_THRESHOLD {
    // up to 2x
    result = 1 << Int(flsl(capacity))
  } else {
    // round up to the nearest multiple of `CHUNK_SIZE`
    let rounded = CHUNK_SIZE * (1 + (capacity >> Int(flsl(CHUNK_SIZE)) - 1))
    result = min(rounded, RINGBUFFER_MAX_SIZE)
  }

  return result
}
