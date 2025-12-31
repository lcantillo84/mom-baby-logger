//
//  DailyStats.swift
//  MomBabyLogger
//
//  Daily statistics calculation model
//

import Foundation

struct DailyStats {
    // Diaper counts
    let poopCount: Int
    let wetCount: Int
    let mixedCount: Int

    // Feeding counts and totals
    let breastFeedingCount: Int
    let breastFeedingTotalMinutes: Int
    let bottleFeedingCount: Int
    let bottleFeedingTotalOz: Double
    let formulaFeedingCount: Int
    let formulaFeedingTotalOz: Double

    // Computed properties for display
    var totalDiaperChanges: Int {
        return poopCount + wetCount + mixedCount
    }

    var totalFeedings: Int {
        return breastFeedingCount + bottleFeedingCount + formulaFeedingCount
    }

    // Initialize from array of entries (typically for a single day)
    init(from entries: [EntryWrapper]) {
        // Extract feeding entries
        let feedingEntries = entries.compactMap { entry -> FeedingEntry? in
            if case .feeding(let feeding) = entry {
                return feeding
            }
            return nil
        }

        // Extract diaper entries
        let diaperEntries = entries.compactMap { entry -> DiaperEntry? in
            if case .diaper(let diaper) = entry {
                return diaper
            }
            return nil
        }

        // Calculate breast feeding stats
        let breastFeedings = feedingEntries.filter { $0.type == .breastFeeding }
        self.breastFeedingCount = breastFeedings.count
        let totalSeconds = breastFeedings.reduce(0.0) { $0 + $1.duration }
        self.breastFeedingTotalMinutes = Int(totalSeconds / 60)

        // Calculate bottle feeding stats
        let bottleFeedings = feedingEntries.filter { $0.type == .bottleFeeding }
        self.bottleFeedingCount = bottleFeedings.count
        self.bottleFeedingTotalOz = bottleFeedings.compactMap { $0.amount }.reduce(0, +)

        // Calculate formula feeding stats
        let formulaFeedings = feedingEntries.filter { $0.type == .formulaFeeding }
        self.formulaFeedingCount = formulaFeedings.count
        self.formulaFeedingTotalOz = formulaFeedings.compactMap { $0.amount }.reduce(0, +)

        // Calculate diaper stats
        self.poopCount = diaperEntries.filter { $0.type == .poopDiaper }.count
        self.wetCount = diaperEntries.filter { $0.type == .wetDiaper }.count
        self.mixedCount = diaperEntries.filter { $0.type == .mixedDiaper }.count
    }
}
