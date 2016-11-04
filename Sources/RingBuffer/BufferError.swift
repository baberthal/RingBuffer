//
//  BufferError.swift
//  RingBuffer
//
//  Created by Morgan Lieberthal on 10/10/16.
//
//

/// Represents an error that occurs while using a RingBuffer
public enum RingBufferError: Swift.Error {
  /// There is insufficient space in the buffer
  ///
  /// - requested: The amount of space that was requested
  /// - available: The number of bytes that are available
  case insufficientSpace(requested: Int, available: Int)

  /// There is insufficient data in the buffer
  ///
  /// - requested: The amount of space that was requested
  /// - available: The number of bytes that are available
  case insufficientData(requested: Int, available: Int)

  /// Represents an error that occured while converting a string to UTF8
  case conversionError

  /// Represents an internal error. Please pass a helpful message.
  case `internal`(String)
}

extension RingBufferError: CustomStringConvertible {
  /// A user-friendly error message 
  public var message: String {
    switch self {
    case .insufficientSpace(requested: let req, available: let avail):
      return "Insufficient space in the buffer. " +
             "Requested \(req) bytes, while \(avail) bytes are available."

    case .insufficientData(requested: let req, available: let avail):
      return "Not enough data in the buffer. " +
             "Buffer has \(avail) bytes of data, but \(req) bytes were requested."

    case .conversionError:
      return "An error occured while converting the byte array to UTF8"

    case .internal(let message):
      return "An internal error occured: \(message)"
    }
  }
  
  public var description: String {
    return message
  }
}
