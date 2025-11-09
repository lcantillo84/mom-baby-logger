//
//  FeedingView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

enum FeedingType: String, CaseIterable {
    case breast = "Breast"
    case bottle = "Bottle"
    case formula = "Formula"
}

struct FeedingView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedType: FeedingType = .breast
    @State private var showingBreastTimer = false
    @State private var amount: String = ""
    @State private var notes: String = ""
    @State private var showingConfirmation = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Feeding type selector
                    Picker("Feeding Type", selection: $selectedType) {
                        ForEach(FeedingType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Content based on selected type
                    switch selectedType {
                    case .breast:
                        breastFeedingSection
                    case .bottle:
                        bottleFeedingSection
                    case .formula:
                        formulaFeedingSection
                    }

                    // Notes section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        TextEditor(text: $notes)
                            .frame(height: 80)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("Feeding")
            .sheet(isPresented: $showingBreastTimer) {
                BreastFeedingTimerView()
            }
            .alert("Feeding Logged", isPresented: $showingConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Feeding has been successfully recorded")
            }
        }
    }

    // MARK: - Breast Feeding Section

    private var breastFeedingSection: some View {
        VStack(spacing: 16) {
            Text("Select Side")
                .font(.headline)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                breastButton(side: .left)
                breastButton(side: .right)
            }

            Button(action: {
                showingBreastTimer = true
            }) {
                HStack {
                    Image(systemName: "timer")
                    Text("Use Timer")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private func breastButton(side: BreastSide) -> some View {
        Button(action: {
            logBreastFeeding(side: side, duration: 600) // Default 10 min
        }) {
            VStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 40))
                Text(side.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Quick Log")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Show suggestion if this is the recommended side
                if dataStore.lastBreastSide == (side == .left ? .right : .left) {
                    Text("Suggested")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
            }
            .frame(width: 160, height: 160)
            .background(Color(.systemGray6))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottle Feeding Section

    private var bottleFeedingSection: some View {
        VStack(spacing: 16) {
            Text("Amount (oz)")
                .font(.headline)
                .foregroundColor(.secondary)

            TextField("Enter amount", text: $amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button(action: {
                logBottleFeeding()
            }) {
                HStack {
                    Image(systemName: "drop.fill")
                    Text("Log Bottle Feeding")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .disabled(amount.isEmpty)
        }
        .padding()
    }

    // MARK: - Formula Feeding Section

    private var formulaFeedingSection: some View {
        VStack(spacing: 16) {
            Text("Amount (oz)")
                .font(.headline)
                .foregroundColor(.secondary)

            TextField("Enter amount", text: $amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button(action: {
                logFormulaFeeding()
            }) {
                HStack {
                    Image(systemName: "drop.fill")
                    Text("Log Formula Feeding")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .disabled(amount.isEmpty)
        }
        .padding()
    }

    // MARK: - Logging Functions

    private func logBreastFeeding(side: BreastSide, duration: TimeInterval) {
        let entry = FeedingEntry(
            type: .breastFeeding,
            side: side,
            duration: duration,
            notes: notes.isEmpty ? nil : notes
        )
        dataStore.addFeeding(entry)
        clearForm()
        showingConfirmation = true
    }

    private func logBottleFeeding() {
        guard let amountValue = Double(amount) else { return }

        let entry = FeedingEntry(
            type: .bottleFeeding,
            duration: 0,
            amount: amountValue,
            notes: notes.isEmpty ? nil : notes
        )
        dataStore.addFeeding(entry)
        clearForm()
        showingConfirmation = true
    }

    private func logFormulaFeeding() {
        guard let amountValue = Double(amount) else { return }

        let entry = FeedingEntry(
            type: .formulaFeeding,
            duration: 0,
            amount: amountValue,
            notes: notes.isEmpty ? nil : notes
        )
        dataStore.addFeeding(entry)
        clearForm()
        showingConfirmation = true
    }

    private func clearForm() {
        amount = ""
        notes = ""
    }
}

#Preview {
    FeedingView()
        .environmentObject(DataStore())
}
