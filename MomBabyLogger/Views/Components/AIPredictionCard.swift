//
//  AIPredictionCard.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// This is the prediction card shown at the top of TodayView.
// It shows two things:
//
// 1. PREDICTION ROW — "Next feeding ~4:15 PM"
//    Calculated locally from feeding history. No internet needed.
//    Always visible as long as 2+ feedings have been logged.
//
// 2. ANOMALY ROW — "It's been longer than usual since the last feeding"
//    Only appears when the gap since the last feeding exceeds the
//    baby's personal average by more than 1 hour.
//
// If there's not enough feeding data (< 2 feedings), this entire
// card returns EmptyView() and takes up zero space in TodayView.
//
// All AI-generated content is labeled with an [AI] badge so the
// parent knows it's computed, not a fact. The disclaimer is always
// visible below — pattern observation, not medical advice.
// ─────────────────────────────────────────────────────────────

import SwiftUI

struct AIPredictionCard: View {

    let entries: [EntryWrapper]

    // We call AIInsightsService methods directly (they're synchronous —
    // no network call, no async needed for prediction/anomaly).
    private let ai = AIInsightsService.shared

    var body: some View {
        // Compute prediction synchronously from entries
        // If nil (not enough data), show nothing
        if let (predicted, avgInterval) = ai.predictNextFeeding(from: entries) {
            cardContent(predicted: predicted, avgInterval: avgInterval)
        }
        // EmptyView() is SwiftUI's way of rendering nothing.
        // We don't need an explicit else — the if just produces no view when nil.
    }

    // ─── Card Content ──────────────────────────────────────────────────────
    private func cardContent(predicted: Date, avgInterval: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {

            // ── Header ─────────────────────────────────────────────────────
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "brain")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.primaryAction)

                Text("AI Patterns")
                    .font(AppTheme.Typography.labelMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.primaryText)

                Spacer()

                // [AI] badge — signals this is generated content, not a fact
                Text("AI")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppTheme.Colors.primaryAction)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppTheme.Colors.primaryAction.opacity(0.12))
                    .cornerRadius(AppTheme.Radius.pill)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.top, AppTheme.Spacing.md)

            Divider()
                .padding(.horizontal, AppTheme.Spacing.md)

            // ── Prediction Row ─────────────────────────────────────────────
            predictionRow(predicted: predicted, avgInterval: avgInterval)

            // ── Anomaly Row (conditional) ──────────────────────────────────
            // Only shown when baby has gone significantly longer than usual.
            // anomalyMessage() returns nil when everything is normal.
            if let nudge = ai.anomalyMessage(from: entries) {
                Divider()
                    .padding(.horizontal, AppTheme.Spacing.md)
                anomalyRow(message: nudge)
            }

            Divider()
                .padding(.horizontal, AppTheme.Spacing.md)

            // ── Disclaimer — always visible ────────────────────────────────
            // Three layers of safety:
            // 1. System prompt constrains Claude (for the digest feature)
            // 2. [AI] badge in the header signals generated content
            // 3. This disclaimer text — always present regardless of content
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.Colors.tertiaryText)
                Text("Pattern estimate only — not medical advice.")
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.tertiaryText)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.md)
        }
        // Card styling — matches existing DailyStatsSection and chart cards exactly
        .background(AppTheme.Colors.cardBackground)
        .cornerRadius(AppTheme.Radius.card)
        .modifier(CardShadow())
        .padding(.horizontal)
    }

    // ─── Prediction Row ────────────────────────────────────────────────────
    private func predictionRow(predicted: Date, avgInterval: TimeInterval) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Icon circle — same style as ActivityRowView icons
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.primaryAction.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: "clock")
                    .font(.system(size: 16))
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }

            VStack(alignment: .leading, spacing: 2) {
                // The predicted time
                Text("Next feeding ~\(predicted, style: .time)")
                    .font(AppTheme.Typography.bodyLarge)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.primaryText)

                // The average interval that drove the prediction
                Text("avg interval \(ai.formatInterval(avgInterval)) across recent feedings")
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    // ─── Anomaly Row ───────────────────────────────────────────────────────
    private func anomalyRow(message: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 15))
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Longer than usual")
                    .font(AppTheme.Typography.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.primaryText)
                Text(message)
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // Preview with mock feeding entries so the card renders
            AIPredictionCard(entries: [
                .feeding(FeedingEntry(
                    id: UUID(), timestamp: Date().addingTimeInterval(-5400),
                    type: .bottleFeeding, side: nil, duration: 0, amount: 3.5, notes: nil
                )),
                .feeding(FeedingEntry(
                    id: UUID(), timestamp: Date().addingTimeInterval(-9000),
                    type: .breastFeeding, side: .left, duration: 900, amount: nil, notes: nil
                )),
                .feeding(FeedingEntry(
                    id: UUID(), timestamp: Date().addingTimeInterval(-12600),
                    type: .bottleFeeding, side: nil, duration: 0, amount: 4.0, notes: nil
                ))
            ])
        }
        .padding(.vertical)
    }
    .background(AppTheme.Colors.appBackground)
}
