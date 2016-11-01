//
//  ReadWriteLock.swift
//  VimChannelKit
//
//  Created by Morgan Lieberthal on 10/18/16.
//
//

// MARK: - ReadWriteLock

/// The `ReadWriteLock` defines an interface for a 
/// [readers-writer lock](https://en.wikipedia.org/wiki/Readers%E2%80%93writer_lock)
public protocol ReadWriteLock {
  /// Execute `block` with a shared reading lock.
  ///
  /// If the implementing type models a readers-writer lock, this function may
  /// behave differently to `withWriteLock(_:)`.
  ///
  /// - parameter block: The block to execute
  /// - returns: The result of executing `block()`
  func withReadLock<T>(_ block: () throws -> T) rethrows -> T

  /// Attempt to call `block` with a read lock.
  ///
  /// If the lock cannot be immediately taken, return `nil`.
  /// Otherwise, return the result of `block()`
  ///
  /// - parameter block: The block to execute
  /// - returns: The value returned from `block`, or `nil` if the 
  ///   lock could not be immediately acquired
  /// - seealso: withReadLock(_:)
  func withAttemptedReadLock<T>(_ block: () throws -> T) rethrows -> T?

  /// Call `block` with an exclusive writing lock.
  ///
  /// If the implementing type models a readers-writer lock, this function may
  /// behave differently to `withReadLock(_:)`.
  ///
  /// - parameter block: The block to execute
  /// - returns: The result of executing `block()`
  func withWriteLock<T>(_ block: () throws -> T) rethrows -> T
}

/// Provide default implementations for `withWriteLock(_:)`
extension ReadWriteLock {
  /// Call `block` with an exclusive writing lock.
  ///
  /// - parameter block: The block to execute
  /// - returns: The result of executing `block()`
  public func withWriteLock<T>(_ block: () throws -> T) rethrows -> T {
    return try withReadLock(block)
  }
}

// MARK: - DispatchLock 

import Dispatch

/// A locking construct using a counting semaphore from Grand Central Dispatch.
/// This locking type behaves the same for both read and write locks.
public struct DispatchLock: ReadWriteLock {
  /// Private semaphore for locking
  private let semaphore = DispatchSemaphore(value: 1)

  /// Create an instance
  public init() {}
  
  /// Execute `block` with a shared reading lock.
  /// - parameter block: The block to execute
  /// - returns: The result of executing `block()`
  public func withReadLock<T>(_ block: () throws -> T) rethrows -> T {
    return try withLock(timeout: .distantFuture, block)!
  }

  /// Attempt to call `block` with a read lock.
  /// - parameter block: The block to execute
  /// - returns: The value returned from `block`, or `nil` if the 
  ///   lock could not be immediately acquired
  /// - seealso: withReadLock(_:)
  public func withAttemptedReadLock<T>(_ block: () throws -> T) rethrows -> T? {
    return try withLock(timeout: .now(), block)
  }

  /// Private helper method
  private func withLock<T>(timeout: DispatchTime, _ block: () throws -> T) rethrows -> T? {
    guard semaphore.wait(timeout: timeout) == .success else { return nil }
    defer { semaphore.signal() }
    return try block()
  }
}
