//
//  MommysLogWidget.swift
//  MommysLogWidget
//
// Home screen widget for Mommy's Log. Shows the time since the last feeding and the
// predicted next feeding, read from the shared App Group that the main app writes to
// (see WidgetSnapshotWriter in the app target). No personal data — just two dates.
//

import WidgetKit
import SwiftUI

// MARK: - Shared App Group (must match the app + widget App Groups capability)

private let appGroupID = "group.lilycantilloapp.mommysblog"

private enum SnapshotKey {
    static let lastFeeding = "widget.lastFeeding"
    static let nextFeeding = "widget.nextFeeding"
}

// Brand teal (#5BA89F) — AppTheme isn't available in the widget target, so define locally.
private let brandTeal = Color(red: 0x5B / 255, green: 0xA8 / 255, blue: 0x9F / 255)

// MARK: - Timeline

struct FeedingWidgetEntry: TimelineEntry {
    let date: Date
    let lastFeeding: Date?
    let nextFeeding: Date?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> FeedingWidgetEntry {
        FeedingWidgetEntry(
            date: Date(),
            lastFeeding: Date().addingTimeInterval(-7200),
            nextFeeding: Date().addingTimeInterval(3600)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FeedingWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FeedingWidgetEntry>) -> Void) {
        let entry = readEntry()
        // Refresh ~every 15 minutes so the "x ago" text stays roughly current even
        // when the app isn't opened. The app also reloads timelines on every change.
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func readEntry() -> FeedingWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroupID)
        let last = defaults?.object(forKey: SnapshotKey.lastFeeding) as? Double
        let next = defaults?.object(forKey: SnapshotKey.nextFeeding) as? Double
        return FeedingWidgetEntry(
            date: Date(),
            lastFeeding: last.map { Date(timeIntervalSince1970: $0) },
            nextFeeding: next.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

// MARK: - View

struct MommysLogWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(brandTeal)
                Text("Mommy's Log")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            if let last = entry.lastFeeding {
                Text("LAST FEEDING")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(last, style: .relative)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("ago")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("No feedings yet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Tap to log the first one")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            if let next = entry.nextFeeding {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(brandTeal)
                    Text("Next ~\(next, style: .time)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Widget

struct MommysLogWidget: Widget {
    let kind: String = "MommysLogWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MommysLogWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Feeding Tracker")
        .description("See how long since the last feeding and when the next one's due.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    MommysLogWidget()
} timeline: {
    FeedingWidgetEntry(date: .now, lastFeeding: Date().addingTimeInterval(-5400), nextFeeding: Date().addingTimeInterval(3600))
    FeedingWidgetEntry(date: .now, lastFeeding: nil, nextFeeding: nil)
}
