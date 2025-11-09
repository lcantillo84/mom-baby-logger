//
//  FeedingEntry.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import Foundation

// Model for feeding activities (breast, bottle, or formula)
struct FeedingEntry: ActivityEntry, Equatable {
    let id: UUID
    let timestamp: Date
    let type: ActivityType
    let side: BreastSide? // Only used for breast feeding
    let duration: TimeInterval // Duration in seconds
    let amount: Double? // Amount in oz or ml (for bottle/formula)
    let notes: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: ActivityType,
        side: BreastSide? = nil,
        duration: TimeInterval = 0,
        amount: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.side = side
        self.duration = duration
        self.amount = amount
        self.notes = notes
    }

    // Formatted display for history
    var displayText: String {
        switch type {
        case .breastFeeding:
            let mins = Int(duration / 60)
            let sideText = side?.displayName ?? "Unknown"
            return "\(sideText) breast - \(mins) min"
        case .bottleFeeding:
            if let amount = amount {
                return "Bottle - \(String(format: "%.1f", amount)) oz"
            }
            return "Bottle"
        case .formulaFeeding:
            if let amount = amount {
                return "Formula - \(String(format: "%.1f", amount)) oz"
            }
            return "Formula"
        default:
            return type.displayName
        }
    }
}
