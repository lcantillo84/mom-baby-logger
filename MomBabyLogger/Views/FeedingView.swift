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
    @State private var confirmationMessage: String = ""
    @State private var isLogging = false

    // Breast feeding manual entry
    @State private var selectedSide: BreastSide = .left
    @State private var manualMinutes: Double = 10

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
            .alert("Success!", isPresented: $showingConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(confirmationMessage)
            }
            .onAppear {
                selectedSide = dataStore.lastBreastSide
            }
        }
    }

    // MARK: - Breast Feeding Section

    private var breastFeedingSection: some View {
        VStack(spacing: 20) {
            // Side selector
            VStack(spacing: 12) {
                Text("Select Side")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Picker("Side", selection: $selectedSide) {
                    Text("Left").tag(BreastSide.left)
                    Text("Right").tag(BreastSide.right)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if dataStore.lastBreastSide != selectedSide {
                    Text("✓ Suggested side")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }

            // Manual time entry
            VStack(spacing: 12) {
                Text("Duration: \(Int(manualMinutes)) minutes")
                    .font(.headline)
                    .foregroundColor(.primary)

                HStack(spacing: 16) {
                    Button(action: {
                        if manualMinutes > 1 {
                            manualMinutes -= 1
                            hapticFeedback()
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }

                    Slider(value: $manualMinutes, in: 1...60, step: 1)
                        .tint(.blue)

                    Button(action: {
                        if manualMinutes < 60 {
                            manualMinutes += 1
                            hapticFeedback()
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)

                // Quick time buttons
                HStack(spacing: 12) {
                    quickTimeButton(minutes: 5)
                    quickTimeButton(minutes: 10)
                    quickTimeButton(minutes: 15)
                    quickTimeButton(minutes: 20)
                }
                .padding(.horizontal)
            }

            // Log button
            Button(action: {
                logBreastFeeding(side: selectedSide, duration: manualMinutes * 60)
            }) {
                HStack(spacing: 12) {
                    if isLogging {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Log \(selectedSide.displayName) Breast - \(Int(manualMinutes)) min")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isLogging ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .disabled(isLogging)

            // Divider
            Divider()
                .padding(.vertical, 8)

            // Timer option
            Button(action: {
                showingBreastTimer = true
            }) {
                HStack {
                    Image(systemName: "timer")
                    Text("Use Live Timer Instead")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green.opacity(0.1))
                .foregroundColor(.green)
                .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding()
    }

    private func quickTimeButton(minutes: Int) -> some View {
        Button(action: {
            manualMinutes = Double(minutes)
            hapticFeedback()
        }) {
            Text("\(minutes)m")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(manualMinutes == Double(minutes) ? Color.blue : Color(.systemGray5))
                .foregroundColor(manualMinutes == Double(minutes) ? .white : .primary)
                .cornerRadius(8)
        }
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
        isLogging = true
        hapticSuccess()

        let entry = FeedingEntry(
            type: .breastFeeding,
            side: side,
            duration: duration,
            notes: notes.isEmpty ? nil : notes
        )

        // Simulate brief delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dataStore.addFeeding(entry)
            isLogging = false
            confirmationMessage = "Logged \(side.displayName) breast feeding for \(Int(duration/60)) minutes"
            showingConfirmation = true
            clearForm()

            // Update suggested side for next time
            selectedSide = dataStore.lastBreastSide
        }
    }

    private func logBottleFeeding() {
        guard let amountValue = Double(amount) else { return }

        isLogging = true
        hapticSuccess()

        let entry = FeedingEntry(
            type: .bottleFeeding,
            duration: 0,
            amount: amountValue,
            notes: notes.isEmpty ? nil : notes
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dataStore.addFeeding(entry)
            isLogging = false
            confirmationMessage = "Logged bottle feeding: \(String(format: "%.1f", amountValue)) oz"
            showingConfirmation = true
            clearForm()
        }
    }

    private func logFormulaFeeding() {
        guard let amountValue = Double(amount) else { return }

        isLogging = true
        hapticSuccess()

        let entry = FeedingEntry(
            type: .formulaFeeding,
            duration: 0,
            amount: amountValue,
            notes: notes.isEmpty ? nil : notes
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dataStore.addFeeding(entry)
            isLogging = false
            confirmationMessage = "Logged formula feeding: \(String(format: "%.1f", amountValue)) oz"
            showingConfirmation = true
            clearForm()
        }
    }

    private func clearForm() {
        amount = ""
        notes = ""
    }

    // MARK: - Haptic Feedback

    private func hapticFeedback() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    private func hapticSuccess() {
        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)
    }
}

#Preview {
    FeedingView()
        .environmentObject(DataStore())
}
