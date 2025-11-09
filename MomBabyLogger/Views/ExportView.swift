//
//  ExportView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

enum ExportTimeframe: String, CaseIterable {
    case today = "Today"
    case week = "Last 7 Days"
    case month = "Last 30 Days"
    case all = "All Data"

    func dateRange() -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        case .week:
            let end = now
            let start = calendar.date(byAdding: .day, value: -7, to: end)!
            return (start, end)
        case .month:
            let end = now
            let start = calendar.date(byAdding: .day, value: -30, to: end)!
            return (start, end)
        case .all:
            return nil
        }
    }
}

struct ExportView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var selectedTimeframe: ExportTimeframe = .week
    @State private var showingShareSheet = false
    @State private var exportedText: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Export Timeframe")) {
                    Picker("Timeframe", selection: $selectedTimeframe) {
                        ForEach(ExportTimeframe.allCases, id: \.self) { timeframe in
                            Text(timeframe.rawValue).tag(timeframe)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("Export Format")) {
                    Button(action: exportCSV) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Export as CSV")
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    Button(action: exportText) {
                        HStack {
                            Image(systemName: "text.alignleft")
                            Text("Export as Text Summary")
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    Text("Export your baby's activity data to share with caregivers, doctors, or for your own records.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(items: [exportedText])
            }
        }
    }

    // MARK: - Export Functions

    private func exportCSV() {
        if let range = selectedTimeframe.dateRange() {
            exportedText = dataStore.exportCSV(from: range.start, to: range.end)
        } else {
            exportedText = dataStore.exportCSV()
        }
        showingShareSheet = true
    }

    private func exportText() {
        let calendar = Calendar.current

        if selectedTimeframe == .today {
            let today = calendar.startOfDay(for: Date())
            exportedText = dataStore.exportTextSummary(for: today)
        } else if let range = selectedTimeframe.dateRange() {
            // Generate text summary for date range
            let entries = dataStore.entries(from: range.start, to: range.end)

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium

            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short

            var text = "Baby Activity Summary - \(selectedTimeframe.rawValue)\n\n"

            for entry in entries {
                let date = dateFormatter.string(from: entry.timestamp)
                let time = timeFormatter.string(from: entry.timestamp)
                text += "\(date) at \(time) - \(entry.displayText)\n"
            }

            exportedText = text
        } else {
            // All data
            exportedText = dataStore.exportCSV()
        }

        showingShareSheet = true
    }
}

// Share sheet for iOS
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ExportView()
        .environmentObject(DataStore())
}
