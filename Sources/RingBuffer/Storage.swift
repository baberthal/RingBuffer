//
//  Storage.swift
//  RingBuffer
//
//  Created by Morgan Lieberthal on 11/3/16.
//
//

import Libc

extension RingBufferStorage {
  /// Represents the allocator used to allocate the storage
  enum Allocator {
    // MARK: - Enum Cases

    /// Allocate memory using native Swift APIs
    /// (i.e. `UnsafeMutableRawPointer.allocate(bytes:alignment:)`)
    case swift

    /// Allocate memory using `malloc()`
    case malloc

    /// Allocate memory using `calloc()`
    case calloc

    /// Allocate memory using `mmap()`, passing the file descriptor to map
    case mmap(Int32)

    /// Use a custom allocator
    case custom(alloc: (Int) -> UnsafeMutableRawPointer, dealloc: (UnsafeMutableRawPointer, Int) -> Void)

    // MARK: - Properties

    /// Get the allocator function for the given allocator case
    ///
    /// - returns: a closure to allocate the bytes, that takes the number of bytes
    ///   to be allocated.
    fileprivate var _allocator: (Int) -> UnsafeMutableRawPointer {
      switch self {
      case .swift:
        return {
          UnsafeMutableRawPointer.allocate(bytes: $0, alignedTo: MemoryLayout<UInt8>.alignment)
        }

      case .malloc:
        return { Libc.malloc($0) }

      case .calloc:
        return { Libc.calloc(1, $0) }

      case .mmap(let fd):
        return { Libc.mmap(nil, $0, PROT_READ, MAP_PRIVATE, fd, 0) }

      case .custom(let b, _):
        return { b($0) }
      }
    }

    /// Get the associated deallocator for the given allocator case
    ///
    /// - returns: a closure to deallocate the bytes
    fileprivate var _deallocator: (UnsafeMutableRawPointer, Int) -> Void {
      switch self {
      case .swift:
        return { pointer, len in
          pointer.deallocate(bytes: len, alignedTo: MemoryLayout<UInt8>.alignment)
        }

      case .malloc: fallthrough // falls through to the same deallocator for `calloc()`
      case .calloc:
        return { pointer, _ in
          Libc.free(pointer)
        }

      case .mmap(_):
        return { pointer, len in
          _ = Libc.munmap(pointer, len)
        }

      case .custom(_, let b):
        return { pointer, len in
          b(pointer, len)
        }
      }
    }
  }
}

final class RingBufferStorage {
  /// Capacity of this storage instance, in bytes
  let capacity: Int

  /// Pointer to our allocated memory
  var storagePointer: UnsafeMutableRawPointer!

  /// Base address of the storage, as mapped to UInt8
  var baseAddress: UnsafeMutablePointer<UInt8>?

  /// Allocator to allocate our memory
  let allocator: Allocator

  /// Flag to indicate if this class is responsible for clearing and deinitializing the memory
  private var managingStorage = false

  /// Create an instance of `RingBufferStorage`, with a given `capacity`, using `allocator` to
  /// allocate the memory.
  ///
  /// - parameter capacity: The capacity of the storage to allocate
  ///
  /// - note: `capacity` is rounded up to the nearest page size
  init(capacity: Int, allocator: Allocator = .swift) {
    self.capacity  = roundUpCapacity(capacity)
    self.allocator = allocator
  }

  /// Deallocate our storage, if it exists, upon deinitialization
  deinit {
    self.deallocate()
  }

  /// Allocate the storage's memory
  ///
  /// - parameter clear: Whether or not the storage at `self.storageAddress` should be
  ///   initialized to all zeros. 
  ///
  /// - note: This is a no-op if `self.allocator` is `.calloc`, as
  ///   `calloc()` initializes the memory zeros.
  ///
  /// - note: This is a no-op if `self.allocator` is `.custom`. If you choose to use
  ///   a custom allocator, please initialize the memory yourself.
  ///
  /// - precondition: The memory has not yet been allocated
  /// - postcondition: The memory at `self.storageAddress` is allocated
  func allocate(shouldClear: Bool = true) {
    // assert that we have not yet allocated our memory
    precondition(self.storagePointer == nil, "Memory is already allocated!")

    // if we initialize the storage, we should be responsible for deinitializing it
    self.managingStorage = shouldClear

    // do the memory allocation
    self.storagePointer = self.allocator._allocator(self.capacity)

    // make sure we set our base address before returning from this function
    defer { self.setBaseAddress() }

    // return if we don't want to zero the bytes
    guard shouldClear else { return }

    // if we get here, that means the class is responsible for managing its own memory

    switch self.allocator {
    case .swift: self.baseAddress = self.storagePointer.initializeMemory(as: UInt8.self, to: 0)
    case .malloc: _ = Libc.memset(self.storagePointer, 0, self.capacity)
    default: break
    }
  }

  /// Deallocate this storage's memory
  ///
  /// - precondition: The memory is not initialized
  /// 
  /// - postcondition: The memory has been deallocated
  /// - postcondition: `self.storagePointer` is `nil`
  func deallocate() {
    // return if our pointers are nil
    guard self.storagePointer != nil, self.baseAddress != nil else { return }

    if self.managingStorage {
      self.baseAddress!.deinitialize(count: self.capacity)
      self.baseAddress = nil
    }
    
    self.allocator._deallocator(self.storagePointer, self.capacity)
    self.storagePointer = nil
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

  /// Set the base address of the storage
  private func setBaseAddress() {
    // do nothing if we already set the base address
    guard self.baseAddress == nil else { return }

    self.baseAddress = self.storagePointer.assumingMemoryBound(to: UInt8.self)
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
