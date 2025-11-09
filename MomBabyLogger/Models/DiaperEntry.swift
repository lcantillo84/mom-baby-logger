//
//  DiaperEntry.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import Foundation

// Model for diaper change activities
struct DiaperEntry: ActivityEntry, Equatable {
    let id: UUID
    let timestamp: Date
    let type: ActivityType
    let notes: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: ActivityType,
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.notes = notes
    }

    // Formatted display for history
    var displayText: String {
        return type.displayName
    }
}
