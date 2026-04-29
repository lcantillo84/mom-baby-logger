//
//  InsightsView.swift
//  MomBabyLogger
//

import Charts
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject var dataStore: DataStore
    @ObservedObject private var sync = SyncStateManager.shared
    @State private var showingProGate = false

    private var weekData: [DayInsight] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { i in
            let start = calendar.date(byAdding: .day, value: -i, to: today)!
            let end   = calendar.date(byAdding: .day, value: 1, to: start)!
            let stats = DailyStats(from: dataStore.entries(from: start, to: end))
            let weekday = calendar.component(.weekday, from: start)
            let label = i == 0 ? "Today" : String(calendar.shortWeekdaySymbols[weekday - 1].prefix(3))
            let totalOz = stats.bottleFeedingTotalOz + stats.formulaFeedingTotalOz
            return DayInsight(label: label, feedingCount: stats.totalFeedings, diaperCount: stats.totalDiaperChanges, totalOz: totalOz)
        }
    }

    private var weeklyTotalFeedings: Int { weekData.reduce(0) { $0 + $1.feedingCount } }
    private var weeklyTotalDiapers:  Int { weekData.reduce(0) { $0 + $1.diaperCount } }
    private var weeklyTotalOz:      Double { weekData.reduce(0) { $0 + $1.totalOz } }
    private var hasAnyOz: Bool { weeklyTotalOz > 0 }

    var body: some View {
        NavigationStack {
            Group {
                if sync.isPro || sync.isParticipant {
                    insightsContent
                } else {
                    lockedContent
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Colors.appBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .sheet(isPresented: $showingProGate) {
            ProGateView()
        }
    }

    // MARK: - Insights Content

    private var insightsContent: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {

                feedingChartCard
                diaperChartCard

                disclaimer
                    .padding(.horizontal)
                    .padding(.bottom, AppTheme.Spacing.xl)
            }
            .padding(.top, AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.appBackground.ignoresSafeArea())
    }

    // MARK: - Feeding Chart Card

    private var feedingChartCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {

            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .foregroundColor(AppTheme.Colors.primaryAction)
                Text("Feedings — Last 7 Days")
                    .font(AppTheme.Typography.sectionHeader)
                    .foregroundColor(AppTheme.Colors.primaryText)
            }
            .padding(.horizontal)

            Chart {
                ForEach(weekData, id: \.label) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Feedings", day.feedingCount)
                    )
                    .foregroundStyle(AppTheme.Colors.primaryAction.gradient)
                    .cornerRadius(6)
                    .annotation(position: .top, alignment: .center) {
                        if day.feedingCount > 0 {
                            Text("\(day.feedingCount)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppTheme.Colors.primaryAction)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let int = value.as(Int.self) {
                            Text("\(int)")
                                .font(AppTheme.Typography.labelSmall)
                                .foregroundColor(AppTheme.Colors.tertiaryText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let str = value.as(String.self) {
                            Text(str)
                                .font(AppTheme.Typography.labelSmall)
                                .foregroundColor(AppTheme.Colors.secondaryText)
                        }
                    }
                }
            }
            .frame(height: 180)
            .padding(.horizontal)

            Text("Total \(weeklyTotalFeedings)  ·  Avg \(String(format: "%.1f", Double(weeklyTotalFeedings) / 7.0))x/day")
                .font(AppTheme.Typography.labelMedium)
                .foregroundColor(AppTheme.Colors.secondaryText)
                .padding(.horizontal)

            // Per-day breakdown table
            feedingBreakdownTable
        }
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.Colors.cardBackground)
        .cornerRadius(AppTheme.Radius.card)
        .modifier(CardShadow())
        .padding(.horizontal)
    }

    // MARK: - Per-Day Breakdown Table

    private var feedingBreakdownTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Day")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Feeds")
                    .frame(width: 52, alignment: .trailing)
                if hasAnyOz {
                    Text("Oz")
                        .frame(width: 60, alignment: .trailing)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.Colors.tertiaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(AppTheme.Colors.appBackground)

            Divider()
                .padding(.horizontal, 16)

            ForEach(weekData, id: \.label) { day in
                HStack {
                    Text(day.label)
                        .font(AppTheme.Typography.labelMedium)
                        .foregroundColor(AppTheme.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(day.feedingCount)")
                        .font(.system(size: 14, weight: day.feedingCount > 0 ? .semibold : .regular))
                        .foregroundColor(day.feedingCount > 0 ? AppTheme.Colors.primaryAction : AppTheme.Colors.tertiaryText)
                        .frame(width: 52, alignment: .trailing)
                    if hasAnyOz {
                        Text(day.totalOz > 0 ? String(format: "%.1f", day.totalOz) : "—")
                            .font(.system(size: 14, weight: day.totalOz > 0 ? .semibold : .regular))
                            .foregroundColor(day.totalOz > 0 ? AppTheme.Colors.bottleFeeding : AppTheme.Colors.tertiaryText)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if day.label != weekData.last?.label {
                    Divider()
                        .padding(.horizontal, 16)
                }
            }

            if hasAnyOz {
                Divider()
                    .padding(.horizontal, 16)
                HStack {
                    Text("Total")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(weeklyTotalFeedings)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.primaryAction)
                        .frame(width: 52, alignment: .trailing)
                    Text(String(format: "%.1f oz", weeklyTotalOz))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.bottleFeeding)
                        .frame(width: 60, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(AppTheme.Colors.appBackground)
        .cornerRadius(AppTheme.Radius.sm)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Diaper Chart Card

    private var diaperChartCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {

            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .foregroundColor(AppTheme.Colors.poopDiaper)
                Text("Diapers — Last 7 Days")
                    .font(AppTheme.Typography.sectionHeader)
                    .foregroundColor(AppTheme.Colors.primaryText)
            }
            .padding(.horizontal)

            Chart {
                ForEach(weekData, id: \.label) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Diapers", day.diaperCount)
                    )
                    .foregroundStyle(AppTheme.Colors.poopDiaper.gradient)
                    .cornerRadius(6)
                    .annotation(position: .top, alignment: .center) {
                        if day.diaperCount > 0 {
                            Text("\(day.diaperCount)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppTheme.Colors.poopDiaper)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let int = value.as(Int.self) {
                            Text("\(int)")
                                .font(AppTheme.Typography.labelSmall)
                                .foregroundColor(AppTheme.Colors.tertiaryText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let str = value.as(String.self) {
                            Text(str)
                                .font(AppTheme.Typography.labelSmall)
                                .foregroundColor(AppTheme.Colors.secondaryText)
                        }
                    }
                }
            }
            .frame(height: 180)
            .padding(.horizontal)

            Text("Total \(weeklyTotalDiapers)  ·  Avg \(String(format: "%.1f", Double(weeklyTotalDiapers) / 7.0))x/day")
                .font(AppTheme.Typography.labelMedium)
                .foregroundColor(AppTheme.Colors.secondaryText)
                .padding(.horizontal)
                .padding(.bottom, AppTheme.Spacing.sm)
        }
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.Colors.cardBackground)
        .cornerRadius(AppTheme.Radius.card)
        .modifier(CardShadow())
        .padding(.horizontal)
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

    // MARK: - Locked Content

    private var lockedContent: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(AppTheme.Colors.primaryAction.opacity(0.4))
            Text("Insights is a Pro feature")
                .font(AppTheme.Typography.titleMedium)
                .foregroundColor(AppTheme.Colors.primaryText)
            Text("Upgrade to see 7-day feeding and diaper charts, daily averages, and more.")
                .font(AppTheme.Typography.bodyMedium)
                .foregroundColor(AppTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.Spacing.xl)
            Button("Upgrade to Pro") { showingProGate = true }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppTheme.Spacing.xl)
            Spacer()
        }
        .background(AppTheme.Colors.appBackground.ignoresSafeArea())
    }
}

struct DayInsight {
    let label: String
    let feedingCount: Int
    let diaperCount: Int
    let totalOz: Double
}

#Preview {
    InsightsView()
        .environmentObject(DataStore())
}
