//
//  ReminderSettings.swift
//  MomBabyLogger
//
//  User preferences for feeding reminders
//

import Foundation

struct ReminderSettings: Codable {
    var isEnabled: Bool = true
    var intervalHours: Double = 3.0  // Default 3 hours

    // Available interval options (in hours)
    static let intervalOptions: [Double] = [2.0, 2.5, 3.0, 3.5, 4.0]

    // Display text for interval
    var intervalDisplayText: String {
        if intervalHours.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(intervalHours)) hours"
        } else {
            return "\(intervalHours) hours"
        }
    }

    // Convert to seconds for notification scheduling
    var intervalSeconds: TimeInterval {
        return intervalHours * 3600
    }
}

// Extension for UserDefaults persistence
extension ReminderSettings {
    private static let settingsKey = "FeedingReminderSettings"

    static func load() -> ReminderSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(ReminderSettings.self, from: data) else {
            return ReminderSettings() // Return default
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: ReminderSettings.settingsKey)
        }
    }
}
