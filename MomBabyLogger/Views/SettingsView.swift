//
//  SettingsView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore

    // Baby profile — OPTIONAL and PRIVATE BY DESIGN: stored only in this device's
    // UserDefaults. Deliberately NOT synced via CloudKit/Partner Sync and never
    // uploaded anywhere — it only appears on Doctor Visit Reports the parent
    // chooses to share. 0 birthday = not set.
    @AppStorage("mommyslog.babyName") private var babyName: String = ""
    @AppStorage("mommyslog.babyBirthday") private var babyBirthdayInterval: Double = 0

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
        NavigationStack {
            Form {
                // Baby Profile Section — optional, on-device only (see @AppStorage note above)
                Section(
                    header: Text("Baby (Optional)"),
                    footer: Text("Shown on your Doctor Visit Report. Stored only on this phone — never uploaded, synced, or shared unless you share a report.")
                ) {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(AppTheme.Colors.primaryAction)
                        TextField("Baby's name", text: $babyName)
                    }
                    if babyBirthdayInterval > 0 {
                        DatePicker(
                            "Birthday",
                            selection: Binding(
                                get: { Date(timeIntervalSince1970: babyBirthdayInterval) },
                                set: { babyBirthdayInterval = $0.timeIntervalSince1970 }
                            ),
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        Button("Remove Birthday", role: .destructive) {
                            babyBirthdayInterval = 0
                        }
                        .font(.caption)
                    } else {
                        Button {
                            // Default to today; parent adjusts in the picker that appears.
                            babyBirthdayInterval = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
                        } label: {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                    .foregroundColor(AppTheme.Colors.primaryAction)
                                Text("Add Birthday (shows age on report)")
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

                // App-wide medical disclaimer — the one place that covers every
                // feature (logs, insights, predictions, reports, reminders).
                Section(header: Text("Medical Disclaimer")) {
                    Text("Mommy's Log is a personal record-keeping tool, not a medical device. All entries, statistics, charts, predictions, reminders, and reports are based on data you enter manually, may contain errors or omissions, and do not constitute medical advice, diagnosis, or treatment. Never use this app as a substitute for professional medical care — always consult your pediatrician or a qualified healthcare provider with any questions about your baby's health, feeding, or development. If you believe your baby has a medical emergency, call your doctor or emergency services immediately.")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.appBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Colors.appBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
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
            .alert("Data Deleted", isPresented: $showingDeleteSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Successfully deleted \(deletedCount) \(deletedCount == 1 ? "entry" : "entries")")
            }
        }
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
