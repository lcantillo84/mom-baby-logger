//
//  DailyStatsSection.swift
//  MomBabyLogger
//
//  Container view that displays all daily stats using StatsCardView
//

import SwiftUI

struct DailyStatsSection: View {
    let stats: DailyStats

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Text("Today's Summary")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            if stats.totalFeedings == 0 && stats.totalDiaperChanges == 0 {
                // Empty state
                emptyStateView
            } else {
                // Grid of stats cards
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    // Breast feeding card
                    if stats.breastFeedingCount > 0 {
                        StatsCardView(
                            icon: "heart.fill",
                            title: "Breast",
                            count: stats.breastFeedingCount,
                            subtitle: "\(stats.breastFeedingTotalMinutes) min",
                            color: .pink
                        )
                    }

                    // Bottle feeding card
                    if stats.bottleFeedingCount > 0 {
                        StatsCardView(
                            icon: "drop.fill",
                            title: "Bottle",
                            count: stats.bottleFeedingCount,
                            subtitle: String(format: "%.1f oz", stats.bottleFeedingTotalOz),
                            color: .blue
                        )
                    }

                    // Formula feeding card
                    if stats.formulaFeedingCount > 0 {
                        StatsCardView(
                            icon: "drop.triangle.fill",
                            title: "Formula",
                            count: stats.formulaFeedingCount,
                            subtitle: String(format: "%.1f oz", stats.formulaFeedingTotalOz),
                            color: .orange
                        )
                    }

                    // Poop diaper card
                    if stats.poopCount > 0 {
                        StatsCardView(
                            icon: "leaf.fill",
                            title: "Poop",
                            count: stats.poopCount,
                            subtitle: nil,
                            color: .brown
                        )
                    }

                    // Wet diaper card
                    if stats.wetCount > 0 {
                        StatsCardView(
                            icon: "drop.triangle",
                            title: "Wet",
                            count: stats.wetCount,
                            subtitle: nil,
                            color: .cyan
                        )
                    }

                    // Mixed diaper card
                    if stats.mixedCount > 0 {
                        StatsCardView(
                            icon: "drop.triangle.fill",
                            title: "Both",
                            count: stats.mixedCount,
                            subtitle: nil,
                            color: .purple
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("No activities yet today")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Start tracking to see your daily summary")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    let sampleEntries: [EntryWrapper] = [
        .feeding(FeedingEntry(type: .breastFeeding, side: .left, duration: 900)),
        .feeding(FeedingEntry(type: .breastFeeding, side: .right, duration: 1200)),
        .feeding(FeedingEntry(type: .bottleFeeding, amount: 4.0)),
        .diaper(DiaperEntry(type: .wetDiaper)),
        .diaper(DiaperEntry(type: .poopDiaper)),
    ]

    let stats = DailyStats(from: sampleEntries)

    return ScrollView {
        DailyStatsSection(stats: stats)
    }
}
