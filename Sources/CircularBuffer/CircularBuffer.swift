//
//  CircularBuffer.swift
//  VimChannelKit
//
//  Created by Morgan Lieberthal on 10/18/16.
//
//

import RingBuffer

public struct CircularBuffer<T> {
  // MARK: - Private Instance Variables

  /// The read-write lock to protect access
  private var _lock = DispatchLock()
  /// Private array of `T` or `nil`
  private var _array: ContiguousArray<T?>
  /// The current read index
  private var readIdx = 0
  /// The current write index
  private var writeIdx = 0

  // MARK: - Public Instance Variables

  /// The capacity of the buffer
  public private(set) var capacity: Int

  /// True if the buffer has no available space for writing
  public var isFull: Bool {
    return availableSpace(for: .writing) == 0
  }

  /// True if the buffer is empty
  public var isEmpty: Bool {
    return availableSpace(for: .reading) == 0
  }

  // MARK: - Initializers

  /// Initialize a CircularBuffer with a given capacity
  public init(capacity: Int) {
    self.capacity = capacity
    self._array = ContiguousArray(repeating: nil, count: capacity)
  }

  // MARK: - Public Instance Methods

  /// Write an element to the buffer
  ///
  /// - parameter element: The element to write to the buffer
  /// - returns: true if the operation succeeded, false if the buffer is out of space
  public mutating func write(element: T) -> Bool {
    guard !isFull else { return false }

    return _lock.withWriteLock {
      _array[writeIdx % _array.count] = element
      writeIdx += 1
      return true
    }
  }

  /// Append an element to the buffer
  ///
  /// - parameter element: The element to append to the buffer
  public mutating func append(_ element: T) {
    _ = write(element: element)
  }

  /// Append a sequence of elements to the buffer
  ///
  /// - parameter contentsOf: The sequence of elements to append to the buffer
  public mutating func append<S: Sequence>(contentsOf: S) where S.Iterator.Element == T {
    for el in contentsOf {
      _ = write(element: el)
    }
  }

  /// Append a collection of elements to the buffer
  ///
  /// - parameter contentsOf: The collection of elements to append to the buffer
  public mutating func append<C: Collection>(contentsOf: C) where C.Iterator.Element == T {
    for el in contentsOf {
      _ = write(element: el)
    }
  }

  /// Append an element to the buffer
  ///
  /// - parameter element: The element to append to the buffer


  /// Read an element from the buffer
  ///
  /// - returns: the next element, or `nil` if the buffer is empty
  public mutating func read(element: T) -> T? {
    guard !isEmpty else { return nil }

    return _lock.withReadLock {
      guard let el = _array[readIdx % _array.count] else { return nil }
      readIdx += 1
      return el
    }
  }

  /// Append a sequence of elements to the buffer
  ///
  /// - parameter elements: The elements to append to the buffer

  /// Get the amount of available space, for a given operation
  ///
  /// - parameter operation: The operation type to query
  /// - returns: The available space for the given operation
  func availableSpace(for operation: CircularBufferOperation) -> Int {
    switch operation {
    case .reading: return writeIdx - readIdx
    case .writing: return capacity - availableSpace(for: .reading)
    }
  }
}

/// Represents a type of operation that the `CircularBuffer` can perform
public enum CircularBufferOperation {
  /// A read operation
  case reading
  /// A write operation 
  case writing
}
