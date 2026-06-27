//
//  SafeMutex.swift
//  Logr
//
//  Created by martin on 13/11/2025.
//

import Foundation
import os

/// Stand-in for `Synchronization.Mutex` on the iOS 17 floor, for the common
/// case where the protected value is `Sendable`. No unsafe code, no manual
/// `deinit`, checked `Sendable`. `~Copyable`, so it enforces the same
/// unique-ownership discipline as the real type — share it via a class/borrow,
/// not by copying.
///
/// Constraining the closure result to `Sendable` keeps this shim strictly
/// no-more-permissive than `Synchronization.Mutex` (whose result is `sending`,
/// which any `Sendable` value satisfies). So when you raise the floor to iOS 18,
/// swapping `import os` for `import Synchronization` is mechanical: anything that
/// compiles against this compiles against the real type.
struct SafeMutex<Value: Sendable>: ~Copyable, Sendable {
    private let lock: OSAllocatedUnfairLock<Value>

    init(_ initialValue: Value) {
        lock = OSAllocatedUnfairLock(initialState: initialValue)
    }

    borrowing func withLock<Result: Sendable>(_ body: @Sendable (inout Value) throws -> Result) rethrows
        -> Result {
        try lock.withLock(body)
    }

    borrowing func withLockIfAvailable<Result: Sendable>(_ body: @Sendable (inout Value) throws
        -> Result) rethrows -> Result? {
        try lock.withLockIfAvailable(body)
    }
}
 
extension SafeMutex where Value: Copyable {
    /// Snapshot the current value. Each access takes the lock.
    var value: Value {
        withLock { $0 }
    }
}
