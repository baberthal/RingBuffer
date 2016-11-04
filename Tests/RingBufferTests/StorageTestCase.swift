//
//  StorageTestCase.swift
//  RingBuffer
//
//  Created by Morgan Lieberthal on 11/3/16.
//
//

import XCTest
@testable import RingBuffer

class StorageTestCase: XCTestCase {
}

extension Int {
  func times(_ block: () -> Void) {
    for _ in 0..<self {
      block()
    }
  }
}
