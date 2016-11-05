//
//  StorageTests.swift
//  RingBuffer
//
//  Created by Morgan Lieberthal on 11/3/16.
//
//

import XCTest
@testable import RingBuffer

class StorageAllocationTests: XCTestCase {
  override func setUp() {
    super.setUp()
  }
  
  override func tearDown() {
    super.tearDown()
  }

  func testCapacityUnder16() {
    let storage = RingBufferStorage(capacity: 12)
    XCTAssert(storage.capacity == 16 + 1)
  }

  func testCapacityBetween16AndLowerThreshold() {
    let storage = RingBufferStorage(capacity: 32)
    XCTAssert(storage.capacity == 64 + 1, "Got \(storage.capacity)")
  }

  func testCapacityUnderHighThreshold() {
    let storage = RingBufferStorage(capacity: Int(1 << 21))
    XCTAssert(storage.capacity == ((1 << 22) + 1), "Got \(storage.capacity)")
  }
}
