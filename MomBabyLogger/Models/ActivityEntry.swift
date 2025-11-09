//
//  ActivityEntry.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import Foundation

// Base protocol for all activity entries
protocol ActivityEntry: Identifiable, Codable {
    var id: UUID { get }
    var timestamp: Date { get }
    var type: ActivityType { get }
}

// Types of activities that can be logged
enum ActivityType: String, Codable {
    case breastFeeding = "Breast Feeding"
    case bottleFeeding = "Bottle Feeding"
    case formulaFeeding = "Formula Feeding"
    case wetDiaper = "Wet Diaper"
    case poopDiaper = "Poop Diaper"
    case mixedDiaper = "Wet & Poop Diaper"

    var displayName: String {
        return self.rawValue
    }

    var icon: String {
        switch self {
        case .breastFeeding:
            return "heart.fill"
        case .bottleFeeding, .formulaFeeding:
            return "drop.fill"
        case .wetDiaper:
            return "drop.triangle"
        case .poopDiaper:
            return "leaf.fill"
        case .mixedDiaper:
            return "drop.triangle.fill"
        }
    }
}

// Breast side for breast feeding tracking
enum BreastSide: String, Codable {
    case left = "Left"
    case right = "Right"

    var displayName: String {
        return self.rawValue
    }
}
