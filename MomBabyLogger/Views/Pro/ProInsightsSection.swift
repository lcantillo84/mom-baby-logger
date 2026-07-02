//
//  ProInsightsSection.swift
//  MomBabyLogger
//

import SwiftUI

struct ProInsightsSection: View {
    @EnvironmentObject var dataStore: DataStore
    let todayStats: DailyStats
    let isPro: Bool
    var onUnlockTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("Pro Insights")
                    .font(AppTheme.Typography.titleMedium)
                    .foregroundColor(AppTheme.Colors.primaryText)
                Spacer()
                if isPro {
                    Label("Pro", systemImage: "sparkles")
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundColor(AppTheme.Colors.primaryAction)
                }
            }
            .padding(.horizontal)

            if isPro {
                proContent
            } else {
                lockedTeaser
            }
        }
    }

    // MARK: - Pro Content

    private var proContent: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppTheme.Spacing.md
            ) {
                insightCard(
                    icon: "clock.fill",
                    title: "Last Feeding",
                    value: timeSinceLastFeeding,
                    color: AppTheme.Colors.primaryAction
                )
                insightCard(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "vs Yesterday",
                    value: feedingDelta.text,
                    color: feedingDelta.color
                )
                insightCard(
                    icon: "calendar.badge.clock",
                    title: "Daily Avg",
                    value: weeklyAvgText,
                    color: AppTheme.Colors.bottleFeeding
                )
                if totalOzToday > 0 {
                    insightCard(
                        icon: "drop.fill",
                        title: "Total oz Today",
                        value: String(format: "%.1f oz", totalOzToday),
                        color: AppTheme.Colors.formulaFeeding
                    )
                }
            }
            .padding(.horizontal)

            disclaimer
                .padding(.horizontal)
        }
    }

    private func insightCard(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Rectangle()
                .frame(height: 3)
                .foregroundColor(color)
                .cornerRadius(AppTheme.Radius.sm)
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(color)
            Text(value)
                .font(AppTheme.Typography.titleSmall)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.Colors.primaryText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(color.opacity(0.10))
        .cornerRadius(AppTheme.Radius.card)
        .modifier(CardShadow())
    }

    // MARK: - Locked Teaser

    private var lockedTeaser: some View {
        Button(action: onUnlockTap) {
            VStack(spacing: 0) {
                lockedRow(icon: "lock.fill",     iconColor: AppTheme.Colors.primaryAction,
                          title: "Unlock Pro Insights",
                          detail: "Time since last feeding, trends & averages",
                          showDivider: true)
                lockedRow(icon: "brain",          iconColor: AppTheme.Colors.primaryAction,
                          title: "AI Patterns",
                          detail: "Feeding predictions and anomaly alerts",
                          showDivider: false)

                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.tertiaryText)
                        .padding(.trailing, AppTheme.Spacing.sm)
                        .padding(.bottom, AppTheme.Spacing.sm)
                }
            }
            .background(AppTheme.Colors.primaryAction.opacity(0.08))
            .cornerRadius(AppTheme.Radius.card)
            .modifier(CardShadow())
            .padding(.horizontal)
        }
    }

    private func lockedRow(icon: String, iconColor: Color, title: String, detail: String, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(iconColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.Typography.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.Colors.primaryText)
                    Text(detail)
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundColor(AppTheme.Colors.secondaryText)
                }
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)

            if showDivider {
                Divider()
                    .padding(.horizontal, AppTheme.Spacing.md)
            }
        }
    }

    // MARK: - Disclaimer

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "stethoscope")
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.tertiaryText)
            Text("For personal reference only. Always consult your pediatrician for advice about your baby's feeding and development.")
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Calculations

    private var timeSinceLastFeeding: String {
        let last = dataStore.entries
            .compactMap { entry -> Date? in
                if case .feeding = entry { return entry.timestamp }
                return nil
            }
            .max()
        guard let last else { return "—" }
        let interval = Date().timeIntervalSince(last)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m ago"
    }

    private var feedingDelta: (text: String, color: Color) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let yesterday = DailyStats(from: dataStore.entries(from: yesterdayStart, to: todayStart))
        let delta = todayStats.totalFeedings - yesterday.totalFeedings
        if delta > 0 { return ("+\(delta) feeds", AppTheme.Colors.primaryAction) }
        if delta < 0 { return ("\(delta) feeds", AppTheme.Colors.destructiveAction) }
        return ("Same", AppTheme.Colors.secondaryText)
    }

    private var weeklyAvgText: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let total = (0..<7).reduce(0) { sum, i in
            let start = calendar.date(byAdding: .day, value: -i, to: today)!
            let end   = calendar.date(byAdding: .day, value: 1, to: start)!
            return sum + DailyStats(from: dataStore.entries(from: start, to: end)).totalFeedings
        }
        return String(format: "%.1fx/day", Double(total) / 7.0)
    }

    private var totalOzToday: Double {
        todayStats.bottleFeedingTotalOz + todayStats.formulaFeedingTotalOz
    }
}
