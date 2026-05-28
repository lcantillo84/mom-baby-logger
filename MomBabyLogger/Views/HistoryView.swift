//
//  HistoryView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var dataStore: DataStore
    @ObservedObject private var sync = SyncStateManager.shared
    @State private var isRefreshing = false
    @State private var entryToEdit: EntryWrapper?
    @State private var showingPartnerSync = false
    @State private var showingProGate = false

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy (EEEE)"
        return formatter
    }

    var body: some View {
        NavigationStack {
            Group {
                if dataStore.entries.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(dataStore.entriesByDay(), id: \.date) { dayGroup in
                            Section(header: dayHeader(for: dayGroup.date)) {
                                ForEach(dayGroup.entries) { entry in
                                    ActivityRowView(entry: entry)
                                        .listRowBackground(AppTheme.Colors.cardBackground)
                                        .swipeActions(edge: .trailing) {
                                            Button {
                                                entryToEdit = entry
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                            .tint(AppTheme.Colors.primaryAction)

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
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.Colors.appBackground)
                    .refreshable {
                        await refresh()
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Colors.appBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    partnerSyncButton
                }
            }
            .navigationDestination(isPresented: $showingPartnerSync) {
                PartnerSyncView().environmentObject(dataStore)
            }
            .background(AppTheme.Colors.appBackground.ignoresSafeArea())
        }
        .sheet(item: $entryToEdit) { entry in
            EditEntryView(entry: entry)
                .environmentObject(dataStore)
        }
        .sheet(isPresented: $showingProGate) {
            ProGateView()
        }
    }

    private var partnerSyncButton: some View {
        Button {
            if sync.isPro || sync.isParticipant {
                showingPartnerSync = true
            } else {
                showingProGate = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: sync.isPartnerConnected || sync.isParticipant ? "person.2.fill" : "person.2")
                    .foregroundColor(AppTheme.Colors.primaryAction)
                if sync.syncStatus == .syncing {
                    Circle()
                        .fill(sync.syncStatus.color)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -3)
                }
            }
        }
    }

    // MARK: - Views

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.secondaryAction.opacity(0.3))
                    .frame(width: 100, height: 100)
                Image(systemName: "clock.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }

            Text("No Activities Yet")
                .font(AppTheme.Typography.titleSmall)
                .foregroundColor(AppTheme.Colors.primaryText)

            Text("Start tracking feeding and diaper changes to see them here")
                .font(AppTheme.Typography.bodySmall)
                .foregroundColor(AppTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.Colors.appBackground.ignoresSafeArea())
    }

    private func dayHeader(for date: Date) -> some View {
        HStack {
            Text(dateFormatter.string(from: date))
                .font(AppTheme.Typography.sectionHeader)
                .foregroundColor(AppTheme.Colors.primaryText)

            Spacer()

            Text("\(entriesCount(for: date)) activities")
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.secondaryText)
        }
    }

    // MARK: - Helpers

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
        try? await Task.sleep(nanoseconds: 500_000_000)
        isRefreshing = false
    }
}

#Preview {
    HistoryView()
        .environmentObject(DataStore())
}
