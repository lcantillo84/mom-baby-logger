//
//  WidgetSnapshotWriter.swift
//  MomBabyLogger
//
// Mirrors a lightweight snapshot (last feeding time + predicted next feeding) into
// the shared App Group so the home screen widget can display it WITHOUT reading
// DataStore directly. DataStore persists to UserDefaults.standard, which the widget
// process cannot see, and DataStore is off-limits to modify — so this writer is the
// bridge. It only writes aggregate values (two dates); no notes or personal data.
//
// Observes DataStore.$entries and rewrites the snapshot whenever entries change,
// then asks WidgetKit to refresh the timeline.

import Combine
import Foundation
import WidgetKit

@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    // Shared App Group — MUST match the App Groups capability on BOTH the app target
    // and the widget target.
    static let appGroupID = "group.lilycantilloapp.mommysblog"

    enum Key {
        static let lastFeeding = "widget.lastFeeding"   // Double (timeIntervalSince1970)
        static let nextFeeding = "widget.nextFeeding"   // Double (timeIntervalSince1970)
        static let updatedAt   = "widget.updatedAt"     // Double
    }

    private var cancellable: AnyCancellable?
    private let defaults = UserDefaults(suiteName: WidgetSnapshotWriter.appGroupID)

    private init() {}

    /// Begin observing the data store. Call once at app launch.
    func start(observing dataStore: DataStore) {
        write(from: dataStore.entries)
        cancellable = dataStore.$entries
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] entries in
                self?.write(from: entries)
            }
    }

    private func write(from entries: [EntryWrapper]) {
        guard let defaults else { return }

        // Most recent feeding timestamp (any feeding type).
        let lastFeeding = entries
            .compactMap { entry -> Date? in
                if case .feeding(let f) = entry { return f.timestamp }
                return nil
            }
            .max()

        if let lastFeeding {
            defaults.set(lastFeeding.timeIntervalSince1970, forKey: Key.lastFeeding)
        } else {
            defaults.removeObject(forKey: Key.lastFeeding)
        }

        // Predicted next feeding — pure on-device math (nil if <6 feedings in 7 days).
        if let (predicted, _) = AIInsightsService.shared.predictNextFeeding(from: entries) {
            defaults.set(predicted.timeIntervalSince1970, forKey: Key.nextFeeding)
        } else {
            defaults.removeObject(forKey: Key.nextFeeding)
        }

        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)

        WidgetCenter.shared.reloadAllTimelines()
    }
}
