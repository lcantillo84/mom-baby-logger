//
//  SettingsView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore

    @ObservedObject private var sync = SyncStateManager.shared
    @State private var showingProGate = false

    @State private var showingDeleteConfirmation = false
    @State private var deleteTimeframe: DeleteTimeframe = .all
    @State private var showingExportView = false
    @State private var showingDeleteSuccess = false
    @State private var deletedCount = 0

    enum DeleteTimeframe: String, CaseIterable {
        case today = "Today"
        case week = "Last 7 Days"
        case month = "Last 30 Days"
        case all = "All Data"
    }

    var body: some View {
        NavigationView {
            Form {
                // Partner Sync Section
                Section(header: Text("Pro Features")) {
                    if sync.isPro {
                        NavigationLink(destination: PartnerSyncView().environmentObject(dataStore)) {
                            HStack {
                                Image(systemName: sync.isPartnerConnected ? "person.2.fill" : "person.2")
                                    .foregroundColor(AppTheme.Colors.primaryAction)
                                Text("Partner Sync")
                                Spacer()
                                // Tiny sync status badge next to the row
                                Image(systemName: sync.syncStatus.iconName)
                                    .font(.caption)
                                    .foregroundColor(sync.syncStatus.color)
                            }
                        }
                    } else {
                        Button {
                            showingProGate = true
                        } label: {
                            HStack {
                                Image(systemName: "person.2")
                                    .foregroundColor(AppTheme.Colors.primaryAction)
                                Text("Partner Sync")
                                Spacer()
                                Text("PRO")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(AppTheme.Colors.primaryAction)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                // Reminders Section
                Section(header: Text("Reminders")) {
                    NavigationLink(destination: ReminderSettingsView()) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundColor(AppTheme.Colors.primaryAction)
                            Text("Feeding Reminders")
                        }
                    }
                }

                // Export Section
                Section(header: Text("Export")) {
                    Button(action: { showingExportView = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(AppTheme.Colors.bottleFeeding)
                            Text("Export Data")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.tertiaryText)
                        }
                    }
                }

                // Data Management Section
                Section(header: Text("Data Management")) {
                    Picker("Delete Timeframe", selection: $deleteTimeframe) {
                        ForEach(DeleteTimeframe.allCases, id: \.self) { timeframe in
                            Text(timeframe.rawValue).tag(timeframe)
                        }
                    }

                    Button(role: .destructive, action: {
                        showingDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Data")
                        }
                    }
                    .disabled(dataStore.entries.isEmpty)
                }

                // App Info Section
                Section(header: Text("About")) {
                    HStack {
                        Text("Total Entries")
                        Spacer()
                        Text("\(dataStore.entries.count)")
                            .foregroundColor(AppTheme.Colors.secondaryText)
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        Text(AppVersionManager.shared.currentVersion)
                            .foregroundColor(AppTheme.Colors.secondaryText)
                    }
                    
                    #if DEBUG
                    // Debug: Review Status
                    let reviewStatus = ReviewManager.shared.getReviewStatus()
                    HStack {
                        Text("Review Requests")
                        Spacer()
                        Text("\(reviewStatus.requestCount)/3")
                            .foregroundColor(AppTheme.Colors.secondaryText)
                    }
                    
                    if let lastRequest = reviewStatus.lastRequestDate {
                        HStack {
                            Text("Last Review Request")
                            Spacer()
                            Text(lastRequest, style: .date)
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.secondaryText)
                        }
                    }
                    
                    Button(action: {
                        ReviewManager.shared.forceRequestReview()
                    }) {
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Test Review Prompt")
                        }
                    }
                    #endif
                }

                Section {
                    Text("This app helps you track your baby's feeding and diaper changes. All data is stored securely on your device.")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.appBackground)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete \(deleteTimeframe.rawValue)?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    performDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone. Are you sure you want to delete \(deleteTimeframe.rawValue.lowercased())?")
            }
            .sheet(isPresented: $showingExportView) {
                ExportView()
            }
            .sheet(isPresented: $showingProGate) {
                ProGateView()
            }
            .alert("Data Deleted", isPresented: $showingDeleteSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Successfully deleted \(deletedCount) \(deletedCount == 1 ? "entry" : "entries")")
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Delete Functions

    private func performDelete() {
        let calendar = Calendar.current
        let now = Date()

        // Count entries before deletion
        let beforeCount = dataStore.entries.count

        switch deleteTimeframe {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            dataStore.deleteEntries(from: start, to: end)

        case .week:
            let end = now
            let start = calendar.date(byAdding: .day, value: -7, to: end)!
            dataStore.deleteEntries(from: start, to: end)

        case .month:
            let end = now
            let start = calendar.date(byAdding: .day, value: -30, to: end)!
            dataStore.deleteEntries(from: start, to: end)

        case .all:
            dataStore.deleteAllEntries()
        }

        // Count entries after deletion
        let afterCount = dataStore.entries.count
        deletedCount = beforeCount - afterCount

        // Success feedback
        if deletedCount > 0 {
            showingDeleteSuccess = true
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(DataStore())
}
