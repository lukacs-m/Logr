//
//  SafeMutex.swift
//  Logr
//
//  Created by martin on 13/11/2025.
//

import Foundation
import os
import Synchronization

/// A type-erasing protocol for mutex implementations
public protocol MutexProtected<Value>: Sendable {
    associatedtype Value: Sendable

    var value: Value { get }

    func withLock<T: Sendable>(_ block: @Sendable (Value) throws -> T) rethrows -> T

    @discardableResult
    func modify<T: Sendable>(_ block: @Sendable (inout Value) throws -> T) rethrows -> T
}

/// Legacy mutex implementation using OSAllocatedUnfairLock
final class LegacyMutex<Value: Sendable>: MutexProtected {
    private let lock: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        lock = .init(uncheckedState: value)
    }

    var value: Value {
        lock.withLock { $0 }
    }

    func withLock<T: Sendable>(_ block: @Sendable (Value) throws -> T) rethrows -> T {
        try lock.withLock { value in
            try block(value)
        }
    }

    @discardableResult
    func modify<T: Sendable>(_ block: @Sendable (inout Value) throws -> T) rethrows -> T {
        try lock.withLock { state in
            try block(&state)
        }
    }
}

@available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, *)
final class NativeMutex<Value: Sendable>: MutexProtected {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    var value: Value {
        mutex.withLock { $0 }
    }

    func withLock<T: Sendable>(_ block: @Sendable (Value) throws -> T) rethrows -> T {
        try mutex.withLock { value in
            try block(value)
        }
    }

    @discardableResult
    func modify<T: Sendable>(_ block: @Sendable (inout Value) throws -> T) rethrows -> T {
        try mutex.withLock { value in
            try block(&value)
        }
    }
}

/// Factory that creates the appropriate mutex implementation based on availability
public enum SafeMutex {
    /// Creates a thread-safe mutex wrapper for the provided value
    /// using the most appropriate implementation based on platform availability.
    /// - Parameter value: The initial value to protect
    /// - Returns: A thread-safe wrapper conforming to MutexProtocol
    public static func create<Value: Sendable>(_ value: Value) -> any MutexProtected<Value> {
        if #available(iOS 18.0, macOS 15.0, watchOS 11.0, tvOS 18.0, *) {
            NativeMutex(value)
        } else {
            LegacyMutex(value)
        }
    }
}
