//
//  SettingsView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore

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
                // Export Section
                Section(header: Text("Export")) {
                    Button(action: { showingExportView = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Data")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Text("This app helps you track your baby's feeding and diaper changes. All data is stored securely on your device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
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
