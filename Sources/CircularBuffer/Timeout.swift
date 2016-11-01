//
//  Timeout.swift
//  VimChannelKit
//
//  Created by Morgan Lieberthal on 10/18/16.
//
//

import Dispatch

/// An amount of time to wait for a given event.
public enum Timeout {
  /// Do not wait at all.
  case now
  /// Wait indefinitely.
  case forever
  /// Wait for a given number of seconds.
  case interval(Double)
}

extension Timeout {
  /// Raw Value
  var rawValue: DispatchTime {
    switch self {
    case .now:               return DispatchTime.now()
    case .forever:           return DispatchTime.distantFuture
    case .interval(let val): return DispatchTime(uptimeNanoseconds: secondsToNano(val))
    }
  }
}

private func secondsToNano(_ seconds: Double) -> UInt64 {
  return UInt64(seconds * Double(NSEC_PER_SEC))
}
