//
//  TodayView.swift
//  MomBabyLogger
//
//  Today tab showing daily stats and recent activities
//

import SwiftUI

struct TodayView: View {
    @EnvironmentObject var dataStore: DataStore

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
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Daily stats section
                    DailyStatsSection(stats: todayStats)

                    // Divider
                    if !todayEntries.isEmpty {
                        Divider()
                            .padding(.horizontal)
                    }

                    // Recent activities
                    if !todayEntries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Activities")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            ForEach(todayEntries.sorted { $0.timestamp > $1.timestamp }) { entry in
                                ActivityRowView(entry: entry)
                                    .padding(.horizontal)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    TodayView()
        .environmentObject(DataStore())
}
