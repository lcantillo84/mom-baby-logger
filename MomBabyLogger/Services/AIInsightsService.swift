//
//  AIInsightsService.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// This is the AI brain of the app. It provides three things:
//
// 1. predictNextFeeding() — pure Swift math, no internet needed.
//    Looks at all feeding times, finds the average gap between them,
//    and projects forward from the last feeding. Like calculating
//    "the train comes every 30 minutes, last one was 20 min ago,
//    so the next one is in about 10 minutes."
//
// 2. anomalyMessage() — pure Swift math, no internet needed.
//    If the baby has gone significantly longer than usual without
//    a feeding, returns a plain-English nudge. Otherwise nil.
//
// 3. generateDailySummary() — calls Claude API, requires internet.
//    Sends ONLY aggregated stats (no names, no personal data) and
//    streams the response back token by token, like ChatGPT.
//
// SECURITY:
//   - API key lives in Config.swift (gitignored — never on GitHub)
//   - Key is NEVER printed in logs or included in error messages
//   - Only aggregated data is sent (privacy by design)
//
// MEDICAL SAFETY:
//   - Disclaimer is baked into the system prompt at the model level
//   - Claude is constrained to never give medical advice
//   - UI also shows disclaimer independently (defense in depth)
// ─────────────────────────────────────────────────────────────

import Combine
import Foundation

// 📖 SWIFT CONCEPT: @MainActor
// All @Published property changes must happen on the main thread
// so SwiftUI can safely update the UI. @MainActor enforces this.
@MainActor
final class AIInsightsService: ObservableObject {

    // 📖 SWIFT CONCEPT: Singleton
    // One shared instance for the whole app. Any view can observe
    // this object and react when streamedText or isLoading changes.
    static let shared = AIInsightsService()
    private init() {}

    // ─── Published State ───────────────────────────────────────────────────
    // 📖 SWIFT CONCEPT: @Published
    // When any of these change, SwiftUI automatically re-renders
    // every view that's observing this object. This is how the
    // streaming text appears word-by-word without any manual refresh.

    @Published var streamedText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // ─── Feature 1: Next Feeding Prediction ───────────────────────────────

    // Returns (predictedTime, averageInterval) or nil if not enough data.
    //
    // HOW IT WORKS:
    // 1. Pull all feeding timestamps from entries, sort oldest→newest
    // 2. zip([a,b,c], [b,c]) pairs consecutive feedings → compute each gap
    // 3. Discard gaps > 6 hours (overnight sleep would skew the average)
    // 4. Take the mean of remaining gaps
    // 5. Add that mean to the last feeding time = predicted next feeding
    //
    // INTERVIEW TALKING POINT:
    // "It's a moving average on time-series data with outlier filtering.
    //  Pure function — takes data, returns value, zero side effects, easy to unit test."
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
        // Fewer than 6 gives too small a sample to be meaningful.
        guard feedingTimes.count >= 6 else { return nil }

        // zip([a,b,c], [b,c]) → [(a,b), (b,c)]
        // For each pair, compute how many seconds apart they are.
        let intervals = zip(feedingTimes, feedingTimes.dropFirst())
            .map { earlier, later in later.timeIntervalSince(earlier) }
            .filter { gap in
                gap > 0 &&
                gap < 8 * 3600   // ignore gaps > 8 hours (overnight sleep)
            }

        guard !intervals.isEmpty else { return nil }

        // reduce(0, +) adds all values together; divide by count = mean
        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)

        let predictedTime = feedingTimes.last!.addingTimeInterval(averageInterval)
        return (predictedTime, averageInterval)
    }

    // ─── Feature 2: Anomaly Detection ─────────────────────────────────────

    // Returns a plain-English nudge string if the baby has gone
    // more than (average interval + 1 hour) without a feeding.
    // Returns nil otherwise — caller shows nothing.
    //
    // WHY +1 HOUR BUFFER:
    // Without a buffer, the alert would fire every time baby is slightly
    // late, causing alert fatigue. +1 hour means "noticeably unusual."
    //
    // INTERVIEW TALKING POINT:
    // "Threshold-based anomaly detection: mean + buffer as the threshold.
    //  Returning nil collapses the UI card to EmptyView automatically —
    //  no empty-state logic needed in the view."
    func anomalyMessage(from entries: [EntryWrapper]) -> String? {
        guard let (_, avgInterval) = predictNextFeeding(from: entries) else { return nil }

        // Get the most recent feeding time
        let lastFeedingTime = entries
            .compactMap { entry -> Date? in
                if case .feeding(let f) = entry { return f.timestamp }
                return nil
            }
            .max()   // most recent timestamp

        guard let lastFeeding = lastFeedingTime else { return nil }

        let elapsed = Date().timeIntervalSince(lastFeeding)
        let alertThreshold = avgInterval + 3600   // average + 1 hour

        guard elapsed > alertThreshold else { return nil }

        return "It's been \(formatInterval(elapsed)) since the last feeding — your average is \(formatInterval(avgInterval))."
    }

    // ─── Feature 3: AI Daily Digest (Streaming) ───────────────────────────

    // Cache keys — one summary per calendar day, stored in UserDefaults.
    // The date key uses ISO8601 day string (e.g. "2026-06-17") so the cache
    // automatically expires at midnight without any cleanup logic.
    private let kCacheDateKey = "mommyslog.aiSummaryDate"
    private let kCacheTextKey = "mommyslog.aiSummaryText"

    // Calls Claude API with aggregated stats and streams the response.
    //
    // force: false (default) — returns today's cached summary instantly if one exists.
    //                          Zero API cost for tapping "Generate" multiple times per day.
    // force: true            — always calls the API (used by "Regenerate" button).
    //
    // HOW STREAMING WORKS:
    // Instead of waiting for the full response, we request "stream: true".
    // Claude sends back a series of Server-Sent Events (SSE) — one per token.
    // Each event looks like:  data: {"delta":{"text":"word"}}
    // We read them line by line and append each word to streamedText.
    // Because streamedText is @Published, SwiftUI re-renders the Text view
    // after each append — producing the word-by-word typing effect.
    //
    // INTERVIEW TALKING POINT:
    // "URLSession's async byte stream — same wire protocol as ChatGPT.
    //  No third-party libraries, just Foundation. The @Published string
    //  drives SwiftUI's diffing engine; only the Text view re-renders,
    //  not the surrounding cards."
    func generateDailySummary(from entries: [EntryWrapper], force: Bool = false) async {
        // Guard: if a call is already in flight, ignore new taps.
        // Without this, a quick double-tap clears streamedText while the first
        // request is mid-stream, producing corrupted mixed output.
        guard !isLoading else { return }

        // ── Cache check (skipped when force: true) ─────────────────────────
        if !force {
            let today = todayDateString()
            if let cached = UserDefaults.standard.string(forKey: kCacheTextKey),
               UserDefaults.standard.string(forKey: kCacheDateKey) == today,
               !cached.isEmpty {
                streamedText = cached
                errorMessage = nil
                return
            }
        }

        // ── Guard: skip API call if nothing logged today ────────────────────
        // Sending "0 feedings, 0 diapers" to Claude costs tokens and returns
        // a useless response. Surface a local message instead.
        let dayStart = Calendar.current.startOfDay(for: Date())
        let todayEntries = entries.filter { $0.timestamp >= dayStart }
        if todayEntries.isEmpty {
            streamedText = "No activities logged today yet. Start logging feedings and diapers to get an AI summary."
            errorMessage = nil
            return
        }

        streamedText = ""
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }   // always runs when function exits, even on error

        // ── Build the API request ──────────────────────────────────────────

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            errorMessage = "Invalid API endpoint"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Key comes from gitignored Config.swift — never hardcoded here
        request.setValue(Config.claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // ── System prompt: medical disclaimer at the model level ───────────
        // This constrains Claude's behavior at the API level, not just the UI.
        // Even if our UI disclaimer is removed, Claude still won't give advice.
        let systemPrompt = """
        You are a baby tracking assistant that observes patterns in feeding and diaper log data.
        You must always follow these rules:
        1. Only describe patterns you observe in the numbers — never tell the parent what to do
        2. Never use these words: should, must, need to, recommend, advise, suggest
        3. Write a maximum of 3 short sentences
        4. Your final sentence must always be exactly: "Always consult your pediatrician for any health concerns."
        5. You are not a medical professional — only report what the data shows
        """

        // ── User message: aggregated stats, zero personal info ─────────────
        let userMessage = buildPrompt(from: entries)

        // ── Request body ───────────────────────────────────────────────────
        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",   // fastest + cheapest Claude model
            "max_tokens": 200,                       // keeps response concise
            "stream": true,                          // enables SSE streaming
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMessage]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            errorMessage = "Failed to build request — try again"
            return
        }
        request.httpBody = bodyData

        // ── Stream the response ────────────────────────────────────────────
        do {
            // bytes(for:) returns an AsyncSequence — we read it line by line.
            // This is non-blocking: the function suspends here and resumes
            // each time a new line arrives from the server.
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            // Check HTTP status before reading stream
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                // IMPORTANT: Do NOT log Config.claudeAPIKey here, even for debugging
                errorMessage = "API error (\(http.statusCode)) — check your API key in Config.swift"
                return
            }

            // Each line from the stream is a Server-Sent Event.
            // SSE format:
            //   data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}
            //   data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" world"}}
            //   data: [DONE]
            for try await line in asyncBytes.lines {
                guard line.hasPrefix("data: ") else { continue }

                let jsonString = String(line.dropFirst(6))  // remove "data: " prefix
                guard jsonString != "[DONE]" else { break } // stream finished

                // Parse the JSON to find the text delta
                guard let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let delta = (json["delta"] as? [String: Any])?["text"] as? String
                else { continue }

                // Appending to @Published triggers SwiftUI re-render
                streamedText += delta
            }

            // Cache today's result so subsequent taps are instant and free.
            if !streamedText.isEmpty {
                UserDefaults.standard.set(todayDateString(), forKey: kCacheDateKey)
                UserDefaults.standard.set(streamedText, forKey: kCacheTextKey)
            }

        } catch {
            // Generic message — API key is never exposed in error output
            errorMessage = "Connection failed — check your internet connection and try again"
        }
    }

    // ─── Private Helpers ───────────────────────────────────────────────────

    // Builds the text sent to Claude.
    // PRIVACY RULE: Only aggregate counts and averages — zero personal info.
    // A stranger reading this cannot identify whose baby it is.
    private func buildPrompt(from entries: [EntryWrapper]) -> String {
        let dayStart = Calendar.current.startOfDay(for: Date())
        let todayEntries = entries.filter { $0.timestamp >= dayStart }
        let stats = DailyStats(from: todayEntries)

        // Build feeding breakdown text
        var feedingParts: [String] = []
        if stats.breastFeedingCount > 0 {
            feedingParts.append("\(stats.breastFeedingCount) breast (\(stats.breastFeedingTotalMinutes) min total)")
        }
        if stats.bottleFeedingCount > 0 {
            feedingParts.append("\(stats.bottleFeedingCount) bottle (\(String(format: "%.1f", stats.bottleFeedingTotalOz))oz total)")
        }
        if stats.formulaFeedingCount > 0 {
            feedingParts.append("\(stats.formulaFeedingCount) formula (\(String(format: "%.1f", stats.formulaFeedingTotalOz))oz total)")
        }
        let feedingDetail = feedingParts.isEmpty ? "none" : feedingParts.joined(separator: ", ")

        // Average interval (reuse existing prediction logic)
        let avgIntervalText: String
        if let (_, avg) = predictNextFeeding(from: entries) {
            avgIntervalText = String(format: "%.1f hours", avg / 3600)
        } else {
            avgIntervalText = "not enough data"
        }

        // No names, no timestamps, no notes — aggregates only
        return """
        Baby tracking data — today only. No names or personal information included.
        Feedings: \(stats.totalFeedings) total — \(feedingDetail)
        Average feeding interval: \(avgIntervalText)
        Diaper changes: \(stats.totalDiaperChanges) total — \(stats.wetCount) wet, \(stats.poopCount) poop, \(stats.mixedCount) mixed
        """
    }

    // Returns "2026-06-17" style string for today — used as the cache date key.
    // ISO8601 day string resets naturally at midnight, no cleanup needed.
    // Static so DateFormatter is created once per process, not on every call.
    // DateFormatter is expensive: it parses locale, timezone, and calendar on init.
    private static let cacheDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func todayDateString() -> String {
        AIInsightsService.cacheDateFormatter.string(from: Date())
    }

    // Converts a TimeInterval (seconds) to "2h 30m" or "45m" format
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
