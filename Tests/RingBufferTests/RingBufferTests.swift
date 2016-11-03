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

    let andBackAgain = try! ringBuffer.gets(UInt(bytesWritten))
    XCTAssert(andBackAgain == testString, "Got the wrong string back. " +
      "Got \(andBackAgain.debugDescription), expected \(testString.debugDescription)")

    let someMoreBack = try! ringBuffer.gets(UInt(moreDataLen))
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
      let _ = try ringBuffer.gets(UInt(idx + 4))
    } catch let error as RingBufferError {
      let expectedMessage = "Not enough data in the buffer. " +
                            "Buffer has \(idx) bytes of data, but \(idx + 4) bytes were requested."
      XCTAssert(error.message == expectedMessage, "Wrong error message")
    } catch {
      XCTFail("Wrong error")
    }
  }

  func testWriteFromData() {
    let dummyData = Data(bytes: [1, 3, 4, 2, 1])
    try! ringBuffer.write(from: dummyData)
    XCTAssert(ringBuffer.availableData == UInt(dummyData.count))
  }

  func testWriteFromBufferPointer() {
    let dummyData = ContiguousArray<UInt8>(repeating: 3, count: 10)
    _ = dummyData.withUnsafeBufferPointer { bufPointer in
      try! ringBuffer.write(from: bufPointer)
    }
    XCTAssert(ringBuffer.availableData == UInt(dummyData.count), "Wrong number of bytes written")
  }

  func testReadIntoData() {
    var data = Data()

    let testString = "hello"
    let strLen = testString.lengthOfBytes(using: .utf8)
    try! ringBuffer.write(string: testString)

    XCTAssert(ringBuffer.availableData == UInt(strLen), "Wrong number of bytes written")

    try! ringBuffer.read(into: &data, count: Int(ringBuffer.availableData))

    XCTAssert(data.count == strLen, "Wrong number of bytes read")
    XCTAssertTrue(ringBuffer.isEmpty, "Buffer should now be empty")
  }

  func testReadIntoDataFailure() {
    var data = Data()

    let testString = "hello"
    let strLen = testString.lengthOfBytes(using: .utf8)
    try! ringBuffer.write(string: testString)

    XCTAssert(ringBuffer.availableData == UInt(strLen), "Wrong number of bytes written")

    do {
      try ringBuffer.read(into: &data, count: strLen + 4)
    } catch let error as RingBufferError {
      let expectedMessage = "Not enough data in the buffer. Buffer has \(strLen) bytes of data, " +
                            "but \(strLen + 4) bytes were requested."
      XCTAssert(error.message == expectedMessage)
    } catch {
      XCTFail("Wrong error")
    }
  }

  func testWithUnsafeBufferPointer() {
    let testString = "hello"
    let strLen = testString.lengthOfBytes(using: .utf8)
    try! ringBuffer.write(string: testString)

    ringBuffer.withUnsafeBufferPointer { bufPointer in
      XCTAssert(bufPointer.count == strLen, "Wrong length of bufPointer")
    }
  }


  func testWithUnsafeMutableBufferPointer() {
    let testString = "hello"
    let strLen = testString.lengthOfBytes(using: .utf8)
    try! ringBuffer.write(string: testString)

    ringBuffer.withUnsafeMutableBufferPointer { bufPointer in
      XCTAssert(bufPointer.count == strLen, "Wrong length of bufPointer")
      XCTAssert(bufPointer.baseAddress!.pointee == 0x0068, "Wrong first element")
      bufPointer.baseAddress!.pointee = 0x0079
    }

    let back = try! ringBuffer.gets(UInt(strLen))
    XCTAssert(back == "yello", "Should have mutated the buffer")
  }

  func testAppendByte() {
    let testData = "h".utf8
    XCTAssert(ringBuffer.isEmpty, "Ring buffer should be empty")

    ringBuffer.append(testData.first!)

    XCTAssert(ringBuffer.availableData == 1, "buffer should have 1 byte available")
    XCTAssertFalse(ringBuffer.isEmpty, "Buffer should not be empty")

    let back = try! ringBuffer.gets(1)
    XCTAssert(back == "h", "Got the wrong byte back")
  }
  
  func testAppendByteSequence() {
    let testString = "hello"
    let strlen = testString.lengthOfBytes(using: .utf8)
    let testData = testString.utf8
    XCTAssert(ringBuffer.isEmpty, "Ring buffer should be empty")

    ringBuffer.append(contentsOf: testData)

    XCTAssert(ringBuffer.availableData == UInt(testData.count),
              "buffer should have 1 byte available, not \(ringBuffer.availableData)")
    XCTAssertFalse(ringBuffer.isEmpty, "Buffer should not be empty")

    let back = try! ringBuffer.gets(UInt(strlen))
    XCTAssert(back == testString, "Wrong string back: \(back) vs \(testString)")

    XCTAssert(ringBuffer.isEmpty, "Buffer should be empty: has \(ringBuffer.availableData) bytes")
  }

  func testReset() {
    let testData = "hello".utf8CString
    XCTAssertTrue(ringBuffer.isEmpty, "Buffer should be empty")

    ringBuffer.append(contentsOf: testData)
    XCTAssert(ringBuffer.availableData == UInt(testData.count),
              "Wrong number of bytes written \(ringBuffer.availableData)")

    ringBuffer.reset()

    XCTAssert(ringBuffer.availableData == 0, "Should now be empty")
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
