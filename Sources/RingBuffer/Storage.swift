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
  let capacity: UInt

  /// Pointer to our allocated memory
  var storagePointer: UnsafeMutableRawPointer!

  /// Allocator to allocate our memory
  let allocator: Allocator

  init(capacity: UInt, allocator: Allocator = .swift) {
    self.capacity  = capacity
    self.allocator = allocator
  }

  convenience init(capacity: Int, allocator: Allocator = .swift) {
    self.init(capacity: UInt(capacity), allocator: allocator)
  }
}
