//
//  BreastFeedingTimerView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct BreastFeedingTimerView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var selectedSide: BreastSide
    @State private var elapsedTime: TimeInterval = 0
    @State private var isRunning = false
    @State private var timer: Timer?
    @State private var notes: String = ""

    init() {
        // Initialize with suggested side
        _selectedSide = State(initialValue: .left)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Side selector
                VStack(spacing: 16) {
                    Text("Select Side")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Picker("Side", selection: $selectedSide) {
                        Text("Left").tag(BreastSide.left)
                        Text("Right").tag(BreastSide.right)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .disabled(isRunning)
                }

                // Timer display
                VStack(spacing: 16) {
                    Text(timeString(from: elapsedTime))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    Text(isRunning ? "Timer Running" : "Ready to Start")
                        .font(.headline)
                        .foregroundColor(isRunning ? .green : .secondary)
                }

                // Timer controls
                HStack(spacing: 20) {
                    if !isRunning {
                        Button(action: startTimer) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    } else {
                        Button(action: stopTimer) {
                            HStack {
                                Image(systemName: "stop.fill")
                                Text("Stop")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }

                    if elapsedTime > 0 {
                        Button(action: resetTimer) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal)

                // Notes
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

                // Save button
                Button(action: saveFeeding) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Feeding")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(elapsedTime > 0 ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .disabled(elapsedTime == 0)

                Spacer()
            }
            .padding(.vertical)
            .navigationTitle("Breast Feeding Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Set suggested side based on last feeding
                selectedSide = dataStore.lastBreastSide
            }
            .onDisappear {
                timer?.invalidate()
            }
        }
    }

    // MARK: - Timer Functions

    private func startTimer() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime += 1
        }
    }

    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func resetTimer() {
        stopTimer()
        elapsedTime = 0
    }

    private func saveFeeding() {
        let entry = FeedingEntry(
            type: .breastFeeding,
            side: selectedSide,
            duration: elapsedTime,
            notes: notes.isEmpty ? nil : notes
        )
        dataStore.addFeeding(entry)
        dismiss()
    }

    // MARK: - Helper Functions

    private func timeString(from timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        let seconds = Int(timeInterval) % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    BreastFeedingTimerView()
        .environmentObject(DataStore())
}
