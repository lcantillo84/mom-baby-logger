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
    @FocusState private var focusedField: FocusField?

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.5

    init() {
        _selectedSide = State(initialValue: .left)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Side selector — custom chips
                VStack(spacing: 12) {
                    Text("Select Side")
                        .font(AppTheme.Typography.sectionHeader)
                        .foregroundColor(AppTheme.Colors.secondaryText)

                    HStack(spacing: 12) {
                        ForEach([BreastSide.left, BreastSide.right], id: \.self) { side in
                            Button(action: { selectedSide = side }) {
                                Text(side.displayName)
                                    .font(AppTheme.Typography.bodyMedium)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        selectedSide == side
                                            ? AppTheme.Colors.primaryAction
                                            : AppTheme.Colors.cardBackground
                                    )
                                    .foregroundColor(
                                        selectedSide == side ? .white : AppTheme.Colors.secondaryText
                                    )
                                    .cornerRadius(AppTheme.Radius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                            .stroke(
                                                selectedSide == side
                                                    ? AppTheme.Colors.primaryAction
                                                    : AppTheme.Colors.secondaryText.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(isRunning)
                            .opacity(isRunning ? 0.6 : 1.0)
                            .animation(.easeInOut(duration: 0.15), value: selectedSide)
                        }
                    }
                    .padding(.horizontal)
                }

                // Timer display with pulse ring
                VStack(spacing: 12) {
                    ZStack {
                        if isRunning {
                            Circle()
                                .stroke(AppTheme.Colors.primaryAction.opacity(pulseOpacity), lineWidth: 2)
                                .frame(width: 180, height: 180)
                                .scaleEffect(pulseScale)
                        }

                        Text(timeString(from: elapsedTime))
                            .font(AppTheme.Typography.displayLarge)
                            .monospacedDigit()
                            .foregroundColor(isRunning ? AppTheme.Colors.primaryAction : AppTheme.Colors.primaryText)
                    }
                    .frame(height: 120)

                    Text(isRunning ? "Timer Running" : "Ready to Start")
                        .font(AppTheme.Typography.bodyMedium)
                        .fontWeight(.medium)
                        .foregroundColor(isRunning ? AppTheme.Colors.primaryAction : AppTheme.Colors.secondaryText)
                }

                // Controls
                HStack(spacing: 16) {
                    if !isRunning {
                        Button(action: startTimer) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Start")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button(action: stopTimer) {
                            HStack {
                                Image(systemName: "stop.fill")
                                Text("Stop")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(AppTheme.Spacing.md)
                            .background(AppTheme.Colors.destructiveAction)
                            .foregroundColor(.white)
                            .cornerRadius(AppTheme.Radius.md)
                        }
                        .buttonStyle(.plain)
                    }

                    if elapsedTime > 0 {
                        Button(action: resetTimer) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(AppTheme.Spacing.md)
                            .background(AppTheme.Colors.warningBanner)
                            .foregroundColor(AppTheme.Colors.primaryText)
                            .cornerRadius(AppTheme.Radius.md)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                // Notes
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes (Optional)")
                        .font(AppTheme.Typography.sectionHeader)
                        .foregroundColor(AppTheme.Colors.secondaryText)

                    TextEditor(text: $notes)
                        .frame(height: 80)
                        .padding(8)
                        .background(AppTheme.Colors.formBackground)
                        .cornerRadius(AppTheme.Radius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .stroke(AppTheme.Colors.secondaryText.opacity(0.15), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .notes)
                }
                .padding(.horizontal)

                // Save button
                Button(action: saveFeeding) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save Feeding")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal)
                .disabled(elapsedTime == 0)

                Spacer()
            }
            .padding(.vertical)
            .background(AppTheme.Colors.appBackground.ignoresSafeArea())
            .dismissKeyboardOnTap()
            .navigationTitle("Breast Feeding Timer")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton(focusedField: $focusedField)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(AppTheme.Colors.primaryAction)
                }
            }
            .onAppear {
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
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            pulseScale = 1.12
            pulseOpacity = 0.1
        }
    }

    private func stopTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        pulseScale = 1.0
        pulseOpacity = 0.5
    }

    private func resetTimer() {
        stopTimer()
        elapsedTime = 0
    }

    private func saveFeeding() {
        focusedField = nil
        let entry = FeedingEntry(
            type: .breastFeeding,
            side: selectedSide,
            duration: elapsedTime,
            notes: notes.isEmpty ? nil : notes
        )
        dataStore.addFeeding(entry)
        dismiss()
    }

    // MARK: - Helpers

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
