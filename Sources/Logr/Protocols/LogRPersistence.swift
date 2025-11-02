//  
//  LogRPersistence.swift
//  Logr
//
//  Created by martin on 02/11/2025.
//

import Foundation

public protocol LogRPersistence: Sendable {
    func store(_ entry: EncryptedLogEntry) async throws
    func fetchEntries() async throws -> [EncryptedLogEntry]
    func deleteEntries(olderThan date: Date) async throws
    func deleteEntries(keepingLatest count: Int) async throws
    func clear() async throws
    func count() async throws -> Int
}
