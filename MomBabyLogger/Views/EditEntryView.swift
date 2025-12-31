//
//  EditEntryView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/26/25.
//

import SwiftUI

struct EditEntryView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss

    let entry: EntryWrapper

    // State for editing
    @State private var timestamp: Date
    @State private var notes: String

    // Feeding-specific states
    @State private var duration: TimeInterval
    @State private var selectedSide: BreastSide
    @State private var amount: Double

    // Diaper-specific states
    @State private var diaperType: ActivityType
    @FocusState private var focusedField: FocusField?

    init(entry: EntryWrapper) {
        self.entry = entry

        // Initialize states based on entry type
        switch entry {
        case .feeding(let feedingEntry):
            _timestamp = State(initialValue: feedingEntry.timestamp)
            _notes = State(initialValue: feedingEntry.notes ?? "")
            _duration = State(initialValue: feedingEntry.duration)
            _selectedSide = State(initialValue: feedingEntry.side ?? .left)
            _amount = State(initialValue: feedingEntry.amount ?? 0.0)
            _diaperType = State(initialValue: .wetDiaper)

        case .diaper(let diaperEntry):
            _timestamp = State(initialValue: diaperEntry.timestamp)
            _notes = State(initialValue: diaperEntry.notes ?? "")
            _diaperType = State(initialValue: diaperEntry.type)
            _duration = State(initialValue: 0)
            _selectedSide = State(initialValue: .left)
            _amount = State(initialValue: 0.0)
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Date & Time")) {
                    DatePicker("Time", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
                }

                // Entry-specific fields
                switch entry {
                case .feeding(let feedingEntry):
                    feedingEditSection(feedingEntry)
                case .diaper:
                    diaperEditSection()
                }

                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                        .focused($focusedField, equals: .notes)
                }
            }
            .dismissKeyboardOnTap()
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton(focusedField: $focusedField)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
        }
    }

    // MARK: - Entry-Specific Sections

    @ViewBuilder
    private func feedingEditSection(_ feedingEntry: FeedingEntry) -> some View {
        Section(header: Text("Feeding Details")) {
            // Show type
            HStack {
                Text("Type")
                Spacer()
                Text(feedingEntry.type.displayName)
                    .foregroundColor(.secondary)
            }

            // Breast feeding specific
            if feedingEntry.type == .breastFeeding {
                Picker("Side", selection: $selectedSide) {
                    Text("Left").tag(BreastSide.left)
                    Text("Right").tag(BreastSide.right)
                }

                HStack {
                    Text("Duration")
                    Spacer()
                    Text("\(Int(duration / 60)) minutes")
                        .foregroundColor(.secondary)
                }

                Slider(value: $duration, in: 0...3600, step: 60)
                    .accentColor(.pink)
            }

            // Bottle/Formula feeding specific
            if feedingEntry.type == .bottleFeeding || feedingEntry.type == .formulaFeeding {
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("0.0", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .focused($focusedField, equals: .amount)
                    Text("oz")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func diaperEditSection() -> some View {
        Section(header: Text("Diaper Details")) {
            Picker("Type", selection: $diaperType) {
                Text("Wet").tag(ActivityType.wetDiaper)
                Text("Poop").tag(ActivityType.poopDiaper)
                Text("Wet & Poop").tag(ActivityType.mixedDiaper)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Save Changes

    private func saveChanges() {
        focusedField = nil
        let updatedEntry: EntryWrapper

        switch entry {
        case .feeding(let feedingEntry):
            let updated = FeedingEntry(
                id: feedingEntry.id,
                timestamp: timestamp,
                type: feedingEntry.type,
                side: feedingEntry.type == .breastFeeding ? selectedSide : nil,
                duration: duration,
                amount: (feedingEntry.type == .bottleFeeding || feedingEntry.type == .formulaFeeding) ? amount : nil,
                notes: notes.isEmpty ? nil : notes
            )
            updatedEntry = .feeding(updated)

        case .diaper(let diaperEntry):
            let updated = DiaperEntry(
                id: diaperEntry.id,
                timestamp: timestamp,
                type: diaperType,
                notes: notes.isEmpty ? nil : notes
            )
            updatedEntry = .diaper(updated)
        }

        dataStore.updateEntry(updatedEntry)
        dismiss()
    }
}
