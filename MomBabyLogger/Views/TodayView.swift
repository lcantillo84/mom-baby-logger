//
//  TodayView.swift
//  MomBabyLogger
//

import SwiftUI

struct TodayView: View {
    @EnvironmentObject var dataStore: DataStore
    @ObservedObject private var sync = SyncStateManager.shared
    @State private var showingProGate = false

    private var todayEntries: [EntryWrapper] {
        let calendar = Calendar.current
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return dataStore.entries(from: dayStart, to: dayEnd)
    }

    private var todayStats: DailyStats {
        return DailyStats(from: todayEntries)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    DailyStatsSection(stats: todayStats)

                    ProInsightsSection(
                        todayStats: todayStats,
                        isPro: sync.isPro || sync.isParticipant,
                        onUnlockTap: { showingProGate = true }
                    )

                    if !todayEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Activities")
                                .font(AppTheme.Typography.titleMedium)
                                .foregroundColor(AppTheme.Colors.primaryText)
                                .padding(.horizontal)

                            ForEach(todayEntries.sorted { $0.timestamp > $1.timestamp }) { entry in
                                ActivityRowView(entry: entry)
                                    .padding(.horizontal, AppTheme.Spacing.md)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.Colors.cardBackground)
                                    .cornerRadius(AppTheme.Radius.lg)
                                    .modifier(CardShadow())
                                    .padding(.horizontal)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.vertical)
            }
            .background(AppTheme.Colors.appBackground.ignoresSafeArea())
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Colors.appBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .sheet(isPresented: $showingProGate) {
            ProGateView()
        }
    }
}

#Preview {
    TodayView()
        .environmentObject(DataStore())
}
