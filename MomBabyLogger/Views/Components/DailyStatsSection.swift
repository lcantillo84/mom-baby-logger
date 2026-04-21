//
//  DailyStatsSection.swift
//  MomBabyLogger
//

import SwiftUI

struct DailyStatsSection: View {
    let stats: DailyStats

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Summary")
                .font(AppTheme.Typography.titleMedium)
                .foregroundColor(AppTheme.Colors.primaryText)
                .padding(.horizontal)

            if stats.totalFeedings == 0 && stats.totalDiaperChanges == 0 {
                emptyStateView
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    if stats.breastFeedingCount > 0 {
                        StatsCardView(
                            icon: "heart.fill",
                            title: "Breast",
                            count: stats.breastFeedingCount,
                            subtitle: "\(stats.breastFeedingTotalMinutes) min",
                            color: AppTheme.Colors.breastFeeding
                        )
                    }
                    if stats.bottleFeedingCount > 0 {
                        StatsCardView(
                            icon: "drop.fill",
                            title: "Bottle",
                            count: stats.bottleFeedingCount,
                            subtitle: String(format: "%.1f oz", stats.bottleFeedingTotalOz),
                            color: AppTheme.Colors.bottleFeeding
                        )
                    }
                    if stats.formulaFeedingCount > 0 {
                        StatsCardView(
                            icon: "drop.triangle.fill",
                            title: "Formula",
                            count: stats.formulaFeedingCount,
                            subtitle: String(format: "%.1f oz", stats.formulaFeedingTotalOz),
                            color: AppTheme.Colors.formulaFeeding
                        )
                    }
                    if stats.poopCount > 0 {
                        StatsCardView(
                            icon: "leaf.fill",
                            title: "Poop",
                            count: stats.poopCount,
                            subtitle: nil,
                            color: AppTheme.Colors.poopDiaper
                        )
                    }
                    if stats.wetCount > 0 {
                        StatsCardView(
                            icon: "drop.triangle",
                            title: "Wet",
                            count: stats.wetCount,
                            subtitle: nil,
                            color: AppTheme.Colors.wetDiaper
                        )
                    }
                    if stats.mixedCount > 0 {
                        StatsCardView(
                            icon: "drop.triangle.fill",
                            title: "Both",
                            count: stats.mixedCount,
                            subtitle: nil,
                            color: AppTheme.Colors.mixedDiaper
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.secondaryAction.opacity(0.3))
                    .frame(width: 80, height: 80)
                Image(systemName: "calendar")
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }
            Text("No activities yet today")
                .font(AppTheme.Typography.bodyLarge)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.Colors.secondaryText)
            Text("Start tracking to see your daily summary")
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

#Preview {
    let sampleEntries: [EntryWrapper] = [
        .feeding(FeedingEntry(type: .breastFeeding, side: .left, duration: 900)),
        .feeding(FeedingEntry(type: .bottleFeeding, amount: 4.0)),
        .diaper(DiaperEntry(type: .wetDiaper)),
        .diaper(DiaperEntry(type: .poopDiaper)),
    ]
    let stats = DailyStats(from: sampleEntries)
    return ScrollView {
        DailyStatsSection(stats: stats)
    }
    .background(AppTheme.Colors.appBackground)
}
