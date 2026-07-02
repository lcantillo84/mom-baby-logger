//
//  AIInsightsService.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// On-device feeding intelligence. Pure Swift math — NO network,
// NO API key, NO third-party calls. Nothing here can be extracted
// or exploited from a shipped binary.
//
// 1. predictNextFeeding() — average gap between recent feedings,
//    projected forward from the last one.
// 2. anomalyMessage() — a plain-English nudge when it's been much
//    longer than usual since the last feeding.
//
// NOTE: the Claude-API "AI Daily Digest" was removed before the public
// release because it required an embedded API key. To bring it back,
// restore it from git history AND route the call through a backend
// proxy so no key ever ships in the app.
// ─────────────────────────────────────────────────────────────

import Foundation

@MainActor
final class AIInsightsService {

    static let shared = AIInsightsService()
    private init() {}

    // ─── Next Feeding Prediction ──────────────────────────────────────────
    // Returns (predictedTime, averageInterval) or nil if not enough data.
    func predictNextFeeding(from entries: [EntryWrapper]) -> (predicted: Date, avgInterval: TimeInterval)? {

        // Only use feedings from the last 7 days — historical averages from weeks
        // ago don't reflect the baby's current pattern and produce misleading predictions.
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let feedingTimes = entries
            .compactMap { entry -> Date? in
                if case .feeding(let f) = entry { return f.timestamp }
                return nil
            }
            .filter { $0 >= sevenDaysAgo }
            .sorted()

        // Require at least 6 feedings before showing a prediction.
        guard feedingTimes.count >= 6 else { return nil }

        // Consecutive gaps, ignoring overnight sleep stretches.
        let intervals = zip(feedingTimes, feedingTimes.dropFirst())
            .map { earlier, later in later.timeIntervalSince(earlier) }
            .filter { gap in
                gap > 0 &&
                gap < 8 * 3600   // ignore gaps > 8 hours (overnight sleep)
            }

        guard !intervals.isEmpty else { return nil }

        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)
        let predictedTime = feedingTimes.last!.addingTimeInterval(averageInterval)
        return (predictedTime, averageInterval)
    }

    // ─── Anomaly Detection ────────────────────────────────────────────────
    // Returns a plain-English nudge if the baby has gone more than
    // (average interval + 1 hour) without a feeding. nil otherwise.
    func anomalyMessage(from entries: [EntryWrapper]) -> String? {
        guard let (_, avgInterval) = predictNextFeeding(from: entries) else { return nil }

        let lastFeedingTime = entries
            .compactMap { entry -> Date? in
                if case .feeding(let f) = entry { return f.timestamp }
                return nil
            }
            .max()

        guard let lastFeeding = lastFeedingTime else { return nil }

        let elapsed = Date().timeIntervalSince(lastFeeding)
        let alertThreshold = avgInterval + 3600   // average + 1 hour

        guard elapsed > alertThreshold else { return nil }

        return "It's been \(formatInterval(elapsed)) since the last feeding — your average is \(formatInterval(avgInterval))."
    }

    // Converts a TimeInterval (seconds) to "2h 30m" or "45m" format.
    func formatInterval(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}
