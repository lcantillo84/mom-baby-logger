//
//  AnalyticsManager.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/15/25.
//

import Foundation

/// Privacy-friendly analytics manager
/// Tracks anonymous usage patterns WITHOUT collecting personal data
/// All data stays on device - nothing is sent to external servers
class AnalyticsManager {

    /// Shared singleton instance
    static let shared = AnalyticsManager()

    private let analyticsKey = "AppAnalytics"

    private init() {}

    // MARK: - Event Tracking

    /// Track when user logs a feeding entry
    func trackFeedingLogged(type: ActivityType) {
        incrementCount(for: "feeding_\(type.rawValue)")
        incrementCount(for: "total_entries")
    }

    /// Track when user logs a diaper entry
    func trackDiaperLogged(type: ActivityType) {
        incrementCount(for: "diaper_\(type.rawValue)")
        incrementCount(for: "total_entries")
    }

    /// Track when user exports data
    func trackDataExport(format: String) {
        incrementCount(for: "export_\(format)")
    }

    /// Track when user deletes data
    func trackDataDeletion(timeframe: String) {
        incrementCount(for: "delete_\(timeframe)")
    }

    /// Track app opens
    func trackAppOpen() {
        incrementCount(for: "app_opens")
        updateLastOpenDate()
    }

    // MARK: - Data Retrieval

    /// Get usage statistics (for your own analysis)
    func getStatistics() -> [String: Int] {
        return UserDefaults.standard.dictionary(forKey: analyticsKey) as? [String: Int] ?? [:]
    }

    /// Get total entries logged
    func getTotalEntries() -> Int {
        let stats = getStatistics()
        return stats["total_entries"] ?? 0
    }

    /// Get most used feature
    func getMostUsedFeature() -> String {
        let stats = getStatistics()

        let feedingCount = (stats["feeding_Breast Feeding"] ?? 0) +
                          (stats["feeding_Bottle Feeding"] ?? 0) +
                          (stats["feeding_Formula Feeding"] ?? 0)

        let diaperCount = (stats["diaper_Wet Diaper"] ?? 0) +
                         (stats["diaper_Poop Diaper"] ?? 0) +
                         (stats["diaper_Wet & Poop Diaper"] ?? 0)

        return feedingCount > diaperCount ? "Feeding" : "Diaper"
    }

    /// Get days active (days user has opened the app)
    func getDaysActive() -> Int {
        // This is an approximation based on app opens
        // More sophisticated tracking would require daily check-ins
        let opens = getStatistics()["app_opens"] ?? 0
        return min(opens, 365) // Cap at 1 year
    }

    // MARK: - Helper Methods

    /// Increment counter for a specific event
    private func incrementCount(for key: String) {
        var stats = getStatistics()
        stats[key] = (stats[key] ?? 0) + 1
        UserDefaults.standard.set(stats, forKey: analyticsKey)
    }

    /// Update last app open date
    private func updateLastOpenDate() {
        UserDefaults.standard.set(Date(), forKey: "last_open_date")
    }

    /// Clear all analytics data (for privacy/testing)
    func clearAllData() {
        UserDefaults.standard.removeObject(forKey: analyticsKey)
    }

    // MARK: - Privacy Report

    /// Generate a privacy-friendly report for debugging
    /// This shows what data is tracked (for transparency)
    func generatePrivacyReport() -> String {
        let stats = getStatistics()

        var report = "=== Mommy's Log Analytics Report ===\n\n"
        report += "PRIVACY NOTICE:\n"
        report += "All data stays on YOUR device.\n"
        report += "Nothing is sent to external servers.\n"
        report += "No personal information is collected.\n\n"
        report += "=== Usage Statistics ===\n"

        for (key, value) in stats.sorted(by: { $0.key < $1.key }) {
            report += "\(key): \(value)\n"
        }

        report += "\n=== Summary ===\n"
        report += "Total Entries: \(getTotalEntries())\n"
        report += "Most Used Feature: \(getMostUsedFeature())\n"
        report += "App Opens: \(stats["app_opens"] ?? 0)\n"

        return report
    }
}
