import XCTest
@testable import RingBuffer

class RingBufferTests: XCTestCase {
  var ringBuffer: RingBuffer!

  override func setUp() {
    super.setUp()
    ringBuffer = RingBuffer(capacity: 2048)
  }

  override func tearDown() {
    ringBuffer = nil
    super.tearDown()
  }

  func testCreation() {
    XCTAssert(ringBuffer != nil, "Unable to allocate ring buffer")
  }

  func testReadWriteString() {
    let testString = "this is a test"
    let testStringLen = testString.lengthOfBytes(using: .utf8)
    let bytesWritten = try! ringBuffer.write(string: testString)
    XCTAssert(bytesWritten == testStringLen,
              "Wrong number of bytes written. Got \(bytesWritten), expected \(testStringLen)")

    XCTAssertFalse(ringBuffer.isEmpty, "Buffer should not be empty!")
    XCTAssertFalse(ringBuffer.isFull, "Buffer should not be full!")

    /// write some more data to the buffer
    let moreData = "this is some more data, you know"
    let _ = try! ringBuffer.write(string: moreData)
    let moreDataLen = moreData.lengthOfBytes(using: .utf8)

    let andBackAgain = try! ringBuffer.gets(bytesWritten)
    XCTAssert(andBackAgain == testString, "Got the wrong string back. " +
      "Got \(andBackAgain.debugDescription), expected \(testString.debugDescription)")

    let someMoreBack = try! ringBuffer.gets(moreDataLen)
    XCTAssert(moreData == someMoreBack, "Got the wrong string back. " +
      "Got \(someMoreBack.debugDescription), expected \(moreData.debugDescription)")
  }

  func testPartialData() {
    let testString = "hello"
    let stringLen  = testString.lengthOfBytes(using: .utf8)
    let written = try! ringBuffer.write(string: testString)

    XCTAssert(written == stringLen,
              "Wrong number of bytes written. Expected \(stringLen), got \(written)")

    let fromBuf = try! ringBuffer.gets(2)
    XCTAssert(fromBuf == "he", "Got the wrong data from the buffer: \(fromBuf)")
  }

  func testFullBuffer() {
    XCTAssertTrue(ringBuffer.isEmpty, "Buffer should be empty")
    XCTAssertFalse(ringBuffer.isFull, "Buffer should not be full")
    let testString = String(repeating: "a", count: 4096)
    let written = try! ringBuffer.write(string: testString)
    XCTAssert(written == 4096, "Wrong number of bytes written to buffer.")
    XCTAssertTrue(ringBuffer.isFull, "Buffer should be full")
  }

  func testInvalidAccessWrite() {
    XCTAssertTrue(ringBuffer.isEmpty, "Buffer should be empty")
    XCTAssertFalse(ringBuffer.isFull, "Buffer should not be full")

    let testString = String(repeating: "a", count: 4099)
    do {
      try ringBuffer.write(string: testString)
    } catch let error as RingBufferError {
      switch error {
      case .insufficientSpace(requested: 4099, available: 4096): XCTAssert(true)
      default: XCTFail("Wrong error message")
      }
    } catch {
      XCTFail("Wrong error")
    }
  }

  func testInvalidAccessRead() {
    XCTAssertTrue(ringBuffer.isEmpty, "Buffer should be empty")
    XCTAssertFalse(ringBuffer.isFull, "Buffer should not be full")

    let testString = "hello"
    try! ringBuffer.write(string: testString)
    XCTAssertFalse(ringBuffer.isEmpty, "Buffer should not be empty")

    let idx = testString.lengthOfBytes(using: .utf8)
    do {
      let _ = try ringBuffer.gets(idx + 4)
    } catch let error as RingBufferError {
      switch error {
      case .insufficientData(requested: idx + 4, available: idx): XCTAssert(true)
      default: XCTFail("Wrong error")
      }
    } catch {
      XCTFail("Wrong error")
    }
  }

  func testWriteFromData() {
    let dummyData = Data(bytes: [1, 3, 4, 2, 1])
    try! ringBuffer.write(from: dummyData)
    XCTAssert(ringBuffer.availableData == dummyData.count)
  }

  func testWriteFromBufferPointer() {
    let dummyData = ContiguousArray<UInt8>(repeating: 3, count: 10)
    _ = dummyData.withUnsafeBufferPointer { bufPointer in
      try! ringBuffer.write(from: bufPointer)
    }
    XCTAssert(ringBuffer.availableData == dummyData.count, "Wrong number of bytes written")
  }

  func testReadIntoData() {
    var data = Data()

    let testString = "hello"
    let strLen = testString.lengthOfBytes(using: .utf8)
    try! ringBuffer.write(string: testString)

    XCTAssert(ringBuffer.availableData == strLen, "Wrong number of bytes written")

    try! ringBuffer.read(into: &data, count: Int(ringBuffer.availableData))

    XCTAssert(data.count == strLen, "Wrong number of bytes read")
    XCTAssertTrue(ringBuffer.isEmpty, "Buffer should now be empty")
  }

  func testReadIntoDataFailure() {
    var data = Data()

    let testString = "hello"
    let strLen = testString.lengthOfBytes(using: .utf8)
    try! ringBuffer.write(string: testString)

    XCTAssert(ringBuffer.availableData == strLen, "Wrong number of bytes written")

    do {
      try ringBuffer.read(into: &data, count: strLen + 4)
    } catch let error as RingBufferError {
      switch error {
      case .insufficientData(requested: strLen + 4, available: strLen): XCTAssert(true)
      default: XCTFail("Wrong error")
      }
    } catch {
      XCTFail("Wrong error")
    }
  }

  func testWithUnsafeBufferPointer() {
    let testString = "hello"
    try! ringBuffer.write(string: testString)

    ringBuffer.withUnsafeBufferPointer { (bufPointer: UnsafeBufferPointer<UInt8>) in
      XCTAssert(bufPointer.first! == 0x0068, "Wrong first element")
    }
  }

  func testWithUnsafeMutableBufferPointer() {
    let testString = "hello"
    let strLen = testString.lengthOfBytes(using: .utf8)
    try! ringBuffer.write(string: testString)

    ringBuffer.withUnsafeMutableBufferPointer { (bufPointer: UnsafeMutableBufferPointer<UInt8>) in
      XCTAssert(bufPointer.baseAddress!.pointee == 0x0068, "Wrong first element")
      bufPointer.baseAddress!.pointee = 0x0079
    }

    let back = try! ringBuffer.gets(strLen)
    XCTAssert(back == "yello", "Should have mutated the buffer")
  }

  func testAppendRawBytes() {
    let testData = UnsafeMutableRawPointer.allocate(
      bytes: 1, alignedTo: MemoryLayout<UInt8>.alignment
    )
    testData.initializeMemory(as: UInt8.self, to: "h".utf8.first!)

    XCTAssert(ringBuffer.isEmpty, "Ring buffer should be empty")

    ringBuffer.append(testData, count: 1)

    XCTAssert(ringBuffer.availableData == 1,
              "buffer should have 1 byte available (has \(ringBuffer.availableData))")
    XCTAssertFalse(ringBuffer.isEmpty, "Buffer should not be empty")

    let back = try! ringBuffer.gets(1)
    XCTAssert(back == "h", "Got the wrong byte back: \(back)")
  }
  
  func testAppendByteSequence() {
    let testString = "hello"
    let strlen = testString.lengthOfBytes(using: .utf8)
    let testData = ContiguousArray(testString.utf8)
    XCTAssert(ringBuffer.isEmpty, "Ring buffer should be empty")

    ringBuffer.append(contentsOf: testData)

    XCTAssert(ringBuffer.availableData == testData.count,
              "buffer should have 1 byte available, not \(ringBuffer.availableData)")
    XCTAssertFalse(ringBuffer.isEmpty, "Buffer should not be empty")

    let back = try! ringBuffer.gets(strlen)
    XCTAssert(back == testString, "Wrong string back: \(back) vs \(testString)")

    XCTAssert(ringBuffer.isEmpty, "Buffer should be empty: has \(ringBuffer.availableData) bytes")
  }

  func testAppendData() {
    // 0x005a == "Z"
    let dummyData = Data(repeating: 0x005a, count: 16)
    XCTAssert(ringBuffer.isEmpty)

    ringBuffer.append(dummyData)
    XCTAssert(ringBuffer.availableData == 16)
    XCTAssert(ringBuffer.count == ringBuffer.availableData)

    // now test getting it back again
    var returnData = Data(capacity: 16)
    try! ringBuffer.read(into: &returnData, count: 16)

    let string = String(data: returnData, encoding: .utf8)!
    XCTAssert(string.utf8.count == 16)
    XCTAssert(string == "ZZZZZZZZZZZZZZZZ")
  }

  func testStringConvertible() {
    let dummyData = Data(repeating: 0x005a, count: 16)
    XCTAssert(ringBuffer.isEmpty)

    ringBuffer.append(dummyData)

    XCTAssert(ringBuffer.description == "16 bytes")
    XCTAssert(ringBuffer.debugDescription == ringBuffer.description)
  }

  func testCustomMirror() {
    let dummyData = Data(repeating: 0x005a, count: 16)
    XCTAssert(ringBuffer.isEmpty)
    ringBuffer.append(dummyData)

    let mirror = ringBuffer.customMirror
    XCTAssert(mirror.displayStyle! == .struct)
    XCTAssert(mirror.children.count == 2)

    debugPrint(mirror)
    debugPrint(mirror.children)
  }

  func testReset() {
    let testData = "hello".utf8CString
    XCTAssertTrue(ringBuffer.isEmpty, "Buffer should be empty")

    ringBuffer.append(contentsOf: testData)
    XCTAssert(ringBuffer.availableData == testData.count,
              "Wrong number of bytes written \(ringBuffer.availableData)")

    ringBuffer.clear()

    XCTAssert(ringBuffer.availableData == 0,
              "Should now be empty (has \(ringBuffer.availableData) bytes available)")
    XCTAssert(ringBuffer.isEmpty, "Should be empty")
  }

  func testDestroy() {
    XCTAssert(ringBuffer != nil, "Ring buffer should not be nil at this point.")
    ringBuffer = nil
    XCTAssert(ringBuffer == nil)
  }
  
  static var allTests : [(String, (RingBufferTests) -> () throws -> Void)] {
    return [
      ("testCreation", testCreation),
      ("testReadWriteString", testReadWriteString),
      ("testPartialData", testPartialData),
      ("testFullBuffer", testFullBuffer),
      ("testInvalidAccessWrite", testInvalidAccessWrite),
      ("testInvalidAccessRead", testInvalidAccessRead),
      ("testWriteFromData", testWriteFromData),
      ("testWriteFromBufferPointer", testWriteFromBufferPointer),
      ("testReadIntoData", testReadIntoData),
      ("testReadIntoDataFailure", testReadIntoDataFailure),
      ("testWithUnsafeBufferPointer", testWithUnsafeBufferPointer),
      ("testWithUnsafeMutableBufferPointer", testWithUnsafeMutableBufferPointer),
      ("testDestroy", testDestroy),
    ]
  }
}
