//
//  AIPredictionCard.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// This is the "Feeding Pattern" card shown near the top of TodayView.
// It shows ONE row: "Estimated next feeding ~4:15 PM", which is simply the
// average gap between the parent's own logged feedings this week, added to
// the last feeding. Calculated on the device. No internet, no AI model.
//
// If there isn't enough feeding data, the card renders nothing.
//
// It is labeled "Estimate" and always shows a short disclaimer. It never
// judges or interprets the timing (no "longer than usual" alerts).
// That row was removed in 1.7.3 for compliance reasons.
// ─────────────────────────────────────────────────────────────

import SwiftUI

struct AIPredictionCard: View {

    let entries: [EntryWrapper]

    // We call AIInsightsService directly (synchronous, plain math,
    // no network call).
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

                Text("Feeding Pattern")
                    .font(AppTheme.Typography.labelMedium)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.primaryText)

                Spacer()

                // "Estimate" badge: signals this is a calculation, not a fact
                Text("Estimate")
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

            Divider()
                .padding(.horizontal, AppTheme.Spacing.md)

            // ── Disclaimer: always visible ────────────────────────────────
            HStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 10))
                    .foregroundColor(AppTheme.Colors.tertiaryText)
                Text("Estimate from your own logs only, not medical advice.")
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
                Text("Estimated next feeding ~\(predicted, style: .time)")
                    .font(AppTheme.Typography.bodyLarge)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.primaryText)

                // The average interval that drove the prediction
                Text("Average gap between your logged feedings this week: \(ai.formatInterval(avgInterval))")
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.secondaryText)
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
