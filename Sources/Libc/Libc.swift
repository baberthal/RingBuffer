//
//  Libc.swift
//  RingBuffer
//
//  Created by Morgan Lieberthal on 11/3/16.
//
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
@_exported import Darwin.C
#elseif os(Linux) || os(FreeBSD) || os(PS4) || os(Android)
@_exported import Glibc
#endif
