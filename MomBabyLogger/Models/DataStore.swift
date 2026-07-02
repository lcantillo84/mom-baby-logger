//
//  DataStore.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import Foundation
import Combine

// Wrapper to handle polymorphic encoding/decoding of ActivityEntry types
enum EntryWrapper: Codable, Identifiable, Equatable {
    case feeding(FeedingEntry)
    case diaper(DiaperEntry)

    var id: UUID {
        switch self {
        case .feeding(let entry): return entry.id
        case .diaper(let entry): return entry.id
        }
    }

    var timestamp: Date {
        switch self {
        case .feeding(let entry): return entry.timestamp
        case .diaper(let entry): return entry.timestamp
        }
    }

    var type: ActivityType {
        switch self {
        case .feeding(let entry): return entry.type
        case .diaper(let entry): return entry.type
        }
    }

    var displayText: String {
        switch self {
        case .feeding(let entry): return entry.displayText
        case .diaper(let entry): return entry.displayText
        }
    }
}

// Main data store for managing all app data
class DataStore: ObservableObject {
    @Published var entries: [EntryWrapper] = []

    // Set to true while we're applying entries received FROM iCloud.
    // CloudKitManager checks this flag to prevent re-uploading data it just downloaded
    // (which would create an infinite sync loop).
    var isApplyingInboundSync: Bool = false

    private let userDefaultsKey = "BabyTrackerEntries"
    private let backupFileURL: URL

    // Last breast side used (to suggest next time)
    @Published var lastBreastSide: BreastSide = .left

    init() {
        // Set up backup file location
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        backupFileURL = documentsPath.appendingPathComponent("baby_tracker_backup.json")

        // Load saved data
        loadData()
    }

    // MARK: - Data Management

    func addFeeding(_ entry: FeedingEntry) {
        entries.append(.feeding(entry))

        // Remember last breast side if applicable
        if let side = entry.side {
            lastBreastSide = side == .left ? .right : .left // Suggest opposite side
        }

        // Track analytics
        AnalyticsManager.shared.trackFeedingLogged(type: entry.type)

        // Request review if appropriate
        ReviewManager.shared.requestReviewIfAppropriate(entryCount: entries.count)

        // Schedule reminder for any feeding type
        scheduleFeedingReminder()

        saveData()
    }

    func addDiaper(_ entry: DiaperEntry) {
        entries.append(.diaper(entry))

        // Track analytics
        AnalyticsManager.shared.trackDiaperLogged(type: entry.type)

        // Request review if appropriate
        ReviewManager.shared.requestReviewIfAppropriate(entryCount: entries.count)

        saveData()
    }

    func deleteEntry(_ entry: EntryWrapper) {
        entries.removeAll { $0.id == entry.id }

        // Recalculate breast side recommendation after deletion
        recalculateLastBreastSide()

        // Reschedule reminder if deleted entry was a feeding
        if case .feeding = entry {
            scheduleFeedingReminder()
        }

        saveData()
    }

    func updateEntry(_ entry: EntryWrapper) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry

            // Update last breast side if it's a feeding entry
            if case .feeding(let feedingEntry) = entry, let side = feedingEntry.side {
                lastBreastSide = side == .left ? .right : .left
            }

            // Reschedule reminder if this is a feeding
            if case .feeding = entry {
                scheduleFeedingReminder()
            }

            saveData()
        }
    }

    func deleteEntries(from startDate: Date, to endDate: Date) {
        entries.removeAll { entry in
            entry.timestamp >= startDate && entry.timestamp <= endDate
        }

        // Recalculate breast side recommendation based on remaining entries
        recalculateLastBreastSide()

        saveData()
    }

    func deleteAllEntries() {
        entries.removeAll()
        lastBreastSide = .left // Reset to default
        saveData()
    }

    /// Removes entries that share a UUID, keeping the first occurrence of each.
    /// Duplicates can arise from concurrent inbound CloudKit syncs (two fetches adding the
    /// same record before either sees the other). They show as doubled rows in History and
    /// break uploads ("can't save the same record twice"). This restores one-entry-per-id
    /// integrity. Idempotent — does nothing when there are no duplicates. Returns the count removed.
    @discardableResult
    func removeDuplicates() -> Int {
        var seen = Set<UUID>()
        var deduped: [EntryWrapper] = []
        for entry in entries where seen.insert(entry.id).inserted {
            deduped.append(entry)
        }
        let removed = entries.count - deduped.count
        if removed > 0 {
            entries = deduped
            saveData()
        }
        return removed
    }

    // MARK: - Data Organization

    // Get entries grouped by day for display
    func entriesByDay() -> [(date: Date, entries: [EntryWrapper])] {
        let calendar = Calendar.current
        let sortedEntries = entries.sorted { $0.timestamp > $1.timestamp }

        var grouped: [Date: [EntryWrapper]] = [:]

        for entry in sortedEntries {
            let dayStart = calendar.startOfDay(for: entry.timestamp)
            if grouped[dayStart] == nil {
                grouped[dayStart] = []
            }
            grouped[dayStart]?.append(entry)
        }

        return grouped.map { (date: $0.key, entries: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { $0.date > $1.date }
    }

    // Get entries within a specific timeframe
    func entries(from startDate: Date, to endDate: Date) -> [EntryWrapper] {
        return entries.filter { entry in
            entry.timestamp >= startDate && entry.timestamp <= endDate
        }.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Persistence

    private func saveData() {
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)

            // Also save to backup file
            try? encoded.write(to: backupFileURL)
        }
    }

    private func loadData() {
        // Try loading from UserDefaults first
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([EntryWrapper].self, from: data) {
            entries = decoded
            recalculateLastBreastSide()
            return
        }

        // If that fails, try loading from backup file
        if let data = try? Data(contentsOf: backupFileURL),
           let decoded = try? JSONDecoder().decode([EntryWrapper].self, from: data) {
            entries = decoded

            // Restore to UserDefaults
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            recalculateLastBreastSide()
            return
        }

        // If both fail, start with empty array
        entries = []
    }

    /// Recalculates the lastBreastSide based on the most recent breast feeding entry
    private func recalculateLastBreastSide() {
        // Find the most recent breast feeding entry
        let breastFeedings = entries.compactMap { entry -> (side: BreastSide, timestamp: Date)? in
            if case .feeding(let feedingEntry) = entry,
               feedingEntry.type == .breastFeeding,
               let side = feedingEntry.side {
                return (side: side, timestamp: feedingEntry.timestamp)
            }
            return nil
        }

        // Sort by timestamp to get the most recent
        if let mostRecent = breastFeedings.sorted(by: { $0.timestamp > $1.timestamp }).first {
            // Suggest the opposite side of the most recent feeding
            lastBreastSide = mostRecent.side == .left ? .right : .left
        } else {
            // No breast feeding history, keep default
            lastBreastSide = .left
        }
    }

    /// Schedule a reminder notification based on the most recent feeding
    private func scheduleFeedingReminder() {
        // Find the most recent feeding entry (any type: breast, bottle, or formula)
        let feedings = entries.compactMap { entry -> Date? in
            if case .feeding(let feedingEntry) = entry {
                return feedingEntry.timestamp
            }
            return nil
        }

        // Get the most recent timestamp
        guard let lastFeedingTime = feedings.sorted(by: { $0 > $1 }).first else {
            // No feedings found, cancel any existing reminders
            Task {
                await NotificationManager.shared.cancelReminder()
            }
            return
        }

        // Load settings and schedule
        let settings = ReminderSettings.load()
        Task {
            await NotificationManager.shared.scheduleReminder(for: lastFeedingTime, settings: settings)
        }
    }

    // MARK: - Inbound Sync

    // Called by CloudKitManager when new entries arrive from iCloud.
    // isApplyingInboundSync = true tells the Combine observer in CloudKitManager
    // "I'm updating entries right now because of an iCloud download — do NOT
    // upload these back or we'll loop forever."
    //
    // 📖 SWIFT CONCEPT: defer
    // `defer { }` runs its block when the function exits, no matter what path
    // the code takes (early return, throw, normal exit). Perfect for cleanup.
    func applyInboundEntries(_ inboundEntries: [EntryWrapper]) {
        isApplyingInboundSync = true
        defer { isApplyingInboundSync = false }

        let existingIDs = Set(entries.map { $0.id })
        let newEntries  = inboundEntries.filter { !existingIDs.contains($0.id) }
        guard !newEntries.isEmpty else { return }

        entries.append(contentsOf: newEntries)
        entries.sort { $0.timestamp > $1.timestamp }
        saveData()
    }

    // MARK: - Export

    func exportCSV(from startDate: Date? = nil, to endDate: Date? = nil) -> String {
        var filteredEntries = entries

        if let start = startDate, let end = endDate {
            filteredEntries = entries(from: start, to: end)
        }

        // Sort chronologically
        filteredEntries.sort { $0.timestamp < $1.timestamp }

        // Create CSV
        var csv = "Date,Time,Activity,Details,Duration,Notes\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        for entry in filteredEntries {
            let date = dateFormatter.string(from: entry.timestamp)
            let time = timeFormatter.string(from: entry.timestamp)
            let activity = entry.type.displayName

            var details = ""
            var duration = ""
            var notes = ""

            switch entry {
            case .feeding(let feedingEntry):
                details = feedingEntry.displayText
                duration = String(format: "%.0f min", feedingEntry.duration / 60)
                notes = feedingEntry.notes ?? ""
            case .diaper(let diaperEntry):
                details = diaperEntry.displayText
                notes = diaperEntry.notes ?? ""
            }

            // Escape quotes in CSV
            let escapedNotes = notes.replacingOccurrences(of: "\"", with: "\"\"")

            csv += "\(date),\(time),\(activity),\(details),\(duration),\"\(escapedNotes)\"\n"
        }

        return csv
    }

    func exportTextSummary(for date: Date) -> String {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let dayEntries = entries(from: dayStart, to: dayEnd)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        var text = "Baby Activity Log - \(dateFormatter.string(from: date))\n\n"

        for entry in dayEntries {
            let time = timeFormatter.string(from: entry.timestamp)
            text += "\(time) - \(entry.displayText)\n"
        }

        return text
    }
}
