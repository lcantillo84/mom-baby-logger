//
//  HistoryView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var isRefreshing = false

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy (EEEE)"
        return formatter
    }

    var body: some View {
        NavigationView {
            Group {
                if dataStore.entries.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(dataStore.entriesByDay(), id: \.date) { dayGroup in
                            Section(header: dayHeader(for: dayGroup.date)) {
                                ForEach(dayGroup.entries) { entry in
                                    ActivityRowView(entry: entry)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                deleteEntry(entry)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        await refresh()
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !dataStore.entries.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(action: {}) {
                                Label("Export Data", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Views

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Activities Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Start tracking feeding and diaper changes to see them here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dayHeader(for date: Date) -> some View {
        HStack {
            Text(dateFormatter.string(from: date))
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            Text("\(entriesCount(for: date)) activities")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helper Functions

    private func entriesCount(for date: Date) -> Int {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return dataStore.entries(from: dayStart, to: dayEnd).count
    }

    private func deleteEntry(_ entry: EntryWrapper) {
        withAnimation {
            dataStore.deleteEntry(entry)
        }
    }

    private func refresh() async {
        isRefreshing = true
        // Simulate a small delay for refresh animation
        try? await Task.sleep(nanoseconds: 500_000_000)
        isRefreshing = false
    }
}

#Preview {
    HistoryView()
        .environmentObject(DataStore())
}
