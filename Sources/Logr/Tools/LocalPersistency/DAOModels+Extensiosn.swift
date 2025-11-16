//  
//  DAOModels+Extensiosn.swift
//  Logr
//
//  Created by Martin Lukacs on 16/11/2025.
//

import Foundation
import SQLiteData

@Table("EncryptedLogEntryDAO")
struct EncryptedLogEntryDAO: Identifiable, Sendable {
    @Column(primaryKey: true) var id: String
    @Column var data: Data // For storing encrypted log data
    @Column var timestamp: TimeInterval

    init(id: String, timestamp: TimeInterval, data: Data) {
        self.id = id
        self.data = data
        self.timestamp = timestamp
    }

    var toEncryptedLogEntry: EncryptedLogEntry {
        EncryptedLogEntry(id: id, timestamp: Date(timeIntervalSince1970: timestamp), data: data)
    }
}

extension EncryptedLogEntry {
    var toEncryptedLogEntryDAO: EncryptedLogEntryDAO {
        EncryptedLogEntryDAO(id: id, timestamp: timestamp.timeIntervalSince1970, data: data)
    }
}
