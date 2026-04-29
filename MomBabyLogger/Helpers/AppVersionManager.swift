//
//  AppVersionManager.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/26/25.
//

import Foundation

class AppVersionManager {
    static let shared = AppVersionManager()

    private let lastVersionKey = "LastAppVersion"
    private let hasSeenWhatsNewKey = "HasSeenWhatsNew_"

    private init() {}

    // MARK: - Version Detection

    var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var lastSavedVersion: String? {
        return UserDefaults.standard.string(forKey: lastVersionKey)
    }

    var isFirstLaunch: Bool {
        return lastSavedVersion == nil
    }

    var isNewVersion: Bool {
        guard let lastVersion = lastSavedVersion else {
            return false // First launch, not an update
        }
        return lastVersion != currentVersion
    }

    // MARK: - What's New Management

    func shouldShowWhatsNew() -> Bool {
        // Don't show on first install
        if isFirstLaunch {
            return false
        }

        // Show if it's a new version and user hasn't seen it yet
        if isNewVersion {
            let hasSeenKey = hasSeenWhatsNewKey + currentVersion
            return !UserDefaults.standard.bool(forKey: hasSeenKey)
        }

        return false
    }

    func markWhatsNewAsSeen() {
        let hasSeenKey = hasSeenWhatsNewKey + currentVersion
        UserDefaults.standard.set(true, forKey: hasSeenKey)
    }

    func updateLastVersion() {
        UserDefaults.standard.set(currentVersion, forKey: lastVersionKey)
    }

    // MARK: - What's New Content

    /// Add your release notes here for each version
    /// Users will see this when they update to that version
    func getWhatsNewContent(for version: String) -> WhatsNewContent? {
        let whatsNewData: [String: WhatsNewContent] = [
            "1.1.0": WhatsNewContent(
                version: "1.1.0",
                title: "Edit Your Logs Anytime!",
                features: [
                    WhatsNewFeature(icon: "pencil.circle.fill", title: "Edit Entries", description: "Fix mistakes or update any feeding or diaper log"),
                    WhatsNewFeature(icon: "hand.draw.fill", title: "Easy Swipe", description: "Swipe left on any entry to edit or delete"),
                    WhatsNewFeature(icon: "clock.fill", title: "Update Details", description: "Change times, amounts, notes, and more")
                ]
            ),

            "1.5.0": WhatsNewContent(
                version: "1.5.0",
                title: "Partner Sync & Insights",
                features: [
                    WhatsNewFeature(icon: "person.2.fill",        title: "Partner Sync",     description: "Share live logs with your partner or nanny via iCloud"),
                    WhatsNewFeature(icon: "chart.bar.fill",       title: "7-Day Insights",   description: "See feeding and diaper charts for the last 7 days"),
                    WhatsNewFeature(icon: "clock.fill",           title: "Quick Stats",       description: "Time since last feeding, daily average, and total oz at a glance"),
                    WhatsNewFeature(icon: "icloud.fill",          title: "iCloud Backup",    description: "Your data is safe even if you switch phones")
                ]
            ),

            // FUTURE UPDATES: Add new versions here
        ]

        return whatsNewData[version]
    }

    func getCurrentWhatsNewContent() -> WhatsNewContent? {
        return getWhatsNewContent(for: currentVersion)
    }
}

// MARK: - Models

struct WhatsNewContent {
    let version: String
    let title: String
    let features: [WhatsNewFeature]
}

struct WhatsNewFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}
