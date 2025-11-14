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
    @State private var selectedFormat: ExportFormat = .csv
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var showingCopySuccess = false

    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case text = "Text"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                    Section(header: Text("Select Timeframe")) {
                        Picker("Timeframe", selection: $selectedTimeframe) {
                            ForEach(ExportTimeframe.allCases, id: \.self) { timeframe in
                                Text(timeframe.rawValue).tag(timeframe)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Section(header: Text("Select Format")) {
                        Picker("Format", selection: $selectedFormat) {
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Copy your data to clipboard, then paste it into:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "envelope.fill")
                                        .foregroundColor(.blue)
                                        .frame(width: 20)
                                    Text("Email app")
                                }
                                HStack {
                                    Image(systemName: "message.fill")
                                        .foregroundColor(.green)
                                        .frame(width: 20)
                                    Text("WhatsApp or Messages")
                                }
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                        .foregroundColor(.orange)
                                        .frame(width: 20)
                                    Text("Notes or any text app")
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                // Copy to clipboard button
                VStack(spacing: 0) {
                    Divider()

                    Button(action: copyToClipboard) {
                        HStack(spacing: 12) {
                            if isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.title3)
                                Text("Copy \(selectedFormat.rawValue) to Clipboard")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(dataStore.entries.isEmpty || isExporting ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(dataStore.entries.isEmpty || isExporting)
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
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
        }
        .alert("Copied!", isPresented: $showingCopySuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Data copied! Open Email, WhatsApp, Notes, or any app and paste (Cmd+V or long-press → Paste).")
        }
    }

    // MARK: - Copy to Clipboard

    private func copyToClipboard() {
        isExporting = true
        errorMessage = nil

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Generate content based on format
            let content: String

            if selectedFormat == .csv {
                // Generate CSV
                if let range = selectedTimeframe.dateRange() {
                    content = dataStore.exportCSV(from: range.start, to: range.end)
                } else {
                    content = dataStore.exportCSV()
                }
            } else {
                // Generate text summary
                if selectedTimeframe == .today {
                    let calendar = Calendar.current
                    let today = calendar.startOfDay(for: Date())
                    content = dataStore.exportTextSummary(for: today)
                } else if let range = selectedTimeframe.dateRange() {
                    let entries = dataStore.entries(from: range.start, to: range.end)
                    content = generateTextSummary(entries: entries, title: selectedTimeframe.rawValue)
                } else {
                    let entries = dataStore.entries.sorted { $0.timestamp < $1.timestamp }
                    content = generateTextSummary(entries: entries, title: "All Data")
                }
            }

            // Copy to clipboard
            UIPasteboard.general.string = content

            isExporting = false

            // Success haptic
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)

            showingCopySuccess = true
        }
    }

    private func generateTextSummary(entries: [EntryWrapper], title: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        var text = "Baby Activity Summary - \(title)\n\n"

        for entry in entries {
            let date = dateFormatter.string(from: entry.timestamp)
            let time = timeFormatter.string(from: entry.timestamp)
            text += "\(date) at \(time) - \(entry.displayText)\n"
        }

        return text
    }

}

#Preview {
    ExportView()
        .environmentObject(DataStore())
}
