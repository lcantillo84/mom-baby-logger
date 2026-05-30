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
    @ObservedObject private var sync = SyncStateManager.shared
    @State private var selectedType: FeedingType = .breast
    @State private var showingBreastTimer = false
    @State private var amount: String = ""
    @State private var notes: String = ""
    @State private var showingConfirmation = false
    @State private var confirmationMessage: String = ""
    @State private var isLogging = false
    @FocusState private var focusedField: FocusField?
    @State private var showingPartnerSync = false
    @State private var showingProGate = false
    @State private var showingSettings = false

    @State private var selectedSide: BreastSide = .left
    @State private var manualMinutes: Double = 10

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Feeding type selector — custom chips
                    HStack(spacing: 8) {
                        ForEach(FeedingType.allCases, id: \.self) { type in
                            Button(action: { selectedType = type }) {
                                Text(type.rawValue)
                                    .font(AppTheme.Typography.bodyMedium)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        selectedType == type
                                            ? AppTheme.Colors.primaryAction
                                            : AppTheme.Colors.cardBackground
                                    )
                                    .foregroundColor(
                                        selectedType == type
                                            ? .white
                                            : AppTheme.Colors.secondaryText
                                    )
                                    .cornerRadius(AppTheme.Radius.md)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                                            .stroke(
                                                selectedType == type
                                                    ? AppTheme.Colors.primaryAction
                                                    : AppTheme.Colors.secondaryText.opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: selectedType)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)

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

                    Spacer()
                }
                .padding(.vertical)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(AppTheme.Colors.appBackground.ignoresSafeArea())
            .dismissKeyboardOnTap()
            .navigationTitle("Feeding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Colors.appBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gear")
                            .foregroundColor(AppTheme.Colors.primaryAction)
                    }
                    partnerSyncButton
                }
            }
            .navigationDestination(isPresented: $showingPartnerSync) {
                PartnerSyncView().environmentObject(dataStore)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView().environmentObject(dataStore)
            }
            .keyboardDoneButton(focusedField: $focusedField)
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
            .sheet(isPresented: $showingProGate) {
                ProGateView()
            }
        }
    }

    private var partnerSyncButton: some View {
        Button {
            if sync.isPro || sync.isParticipant {
                showingPartnerSync = true
            } else {
                showingProGate = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: sync.isPartnerConnected || sync.isParticipant ? "person.2.fill" : "person.2")
                    .foregroundColor(AppTheme.Colors.primaryAction)
                if sync.syncStatus == .syncing {
                    Circle()
                        .fill(sync.syncStatus.color)
                        .frame(width: 7, height: 7)
                        .offset(x: 3, y: -3)
                }
            }
        }
    }

    // MARK: - Breast Feeding Section

    private var breastFeedingSection: some View {
        VStack(spacing: 20) {
            // Recommendation / info banner
            if hasFeedingHistory {
                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(AppTheme.Colors.bottleFeeding)
                        Text("Last used: \(oppositeOf(dataStore.lastBreastSide).displayName) breast")
                            .font(AppTheme.Typography.bodySmall)
                            .fontWeight(.medium)
                            .foregroundColor(AppTheme.Colors.secondaryText)
                        Spacer()
                    }
                    .padding(.horizontal)

                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(AppTheme.Colors.primaryAction)
                        Text("Try: \(dataStore.lastBreastSide.displayName) breast")
                            .font(AppTheme.Typography.bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.Colors.primaryAction)
                        Spacer()
                    }
                    .padding()
                    .background(AppTheme.Colors.successBanner)
                    .cornerRadius(AppTheme.Radius.md)
                    .padding(.horizontal)
                }
                .padding(.top)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(AppTheme.Colors.primaryAction)
                    Text("Start with either breast — the app will track which one to use next")
                        .font(AppTheme.Typography.bodySmall)
                        .foregroundColor(AppTheme.Colors.secondaryText)
                    Spacer()
                }
                .padding()
                .background(AppTheme.Colors.infoBanner)
                .cornerRadius(AppTheme.Radius.md)
                .padding(.horizontal)
                .padding(.top)
            }

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
                        .animation(.easeInOut(duration: 0.15), value: selectedSide)
                    }
                }
                .padding(.horizontal)

                if dataStore.lastBreastSide == oppositeOf(selectedSide) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.Palette.caramel)
                        Text("Same side as last time")
                            .font(AppTheme.Typography.bodySmall)
                            .fontWeight(.medium)
                            .foregroundColor(AppTheme.Palette.caramel)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(AppTheme.Colors.warningBanner)
                    .cornerRadius(AppTheme.Radius.sm)
                    .transition(.opacity)
                }
            }

            // Duration control
            VStack(spacing: 12) {
                Text("Duration: \(Int(manualMinutes)) minutes")
                    .font(AppTheme.Typography.sectionHeader)
                    .foregroundColor(AppTheme.Colors.primaryText)

                HStack(spacing: 16) {
                    Button(action: {
                        if manualMinutes > 1 { manualMinutes -= 1 }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(AppTheme.Colors.primaryAction)
                    }

                    Slider(value: $manualMinutes, in: 1...60, step: 1)
                        .tint(AppTheme.Colors.primaryAction)

                    Button(action: {
                        if manualMinutes < 60 { manualMinutes += 1 }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(AppTheme.Colors.primaryAction)
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 10) {
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
                        Text("Log \(selectedSide.displayName) Breast — \(Int(manualMinutes)) min")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal)
            .disabled(isLogging)

            Divider()
                .padding(.vertical, 4)

            Button(action: {
                showingBreastTimer = true
            }) {
                HStack {
                    Image(systemName: "timer")
                    Text("Use Live Timer Instead")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.horizontal)
        }
        .padding()
    }

    private func quickTimeButton(minutes: Int) -> some View {
        Button(action: {
            manualMinutes = Double(minutes)
        }) {
            Text("\(minutes)m")
                .font(AppTheme.Typography.labelMedium)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    manualMinutes == Double(minutes)
                        ? AppTheme.Colors.primaryAction
                        : AppTheme.Colors.cardBackground
                )
                .foregroundColor(
                    manualMinutes == Double(minutes) ? .white : AppTheme.Colors.secondaryText
                )
                .cornerRadius(AppTheme.Radius.pill)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.pill)
                        .stroke(
                            manualMinutes == Double(minutes)
                                ? AppTheme.Colors.primaryAction
                                : AppTheme.Colors.secondaryText.opacity(0.2),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: manualMinutes)
    }

    // MARK: - Bottle Feeding Section

    private var bottleFeedingSection: some View {
        VStack(spacing: 16) {
            Text("Amount (oz)")
                .font(AppTheme.Typography.sectionHeader)
                .foregroundColor(AppTheme.Colors.secondaryText)

            TextField("Enter amount", text: $amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .focused($focusedField, equals: .amount)

            Button(action: {
                logBottleFeeding()
            }) {
                HStack {
                    Image(systemName: "drop.fill")
                    Text("Log Bottle Feeding")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal)
            .disabled(amount.isEmpty)
        }
        .padding()
    }

    // MARK: - Formula Feeding Section

    private var formulaFeedingSection: some View {
        VStack(spacing: 16) {
            Text("Amount (oz)")
                .font(AppTheme.Typography.sectionHeader)
                .foregroundColor(AppTheme.Colors.secondaryText)

            TextField("Enter amount", text: $amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .focused($focusedField, equals: .amount)

            Button(action: {
                logFormulaFeeding()
            }) {
                HStack {
                    Image(systemName: "drop.fill")
                    Text("Log Formula Feeding")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal)
            .disabled(amount.isEmpty)
        }
        .padding()
    }

    // MARK: - Logging Functions

    private func logBreastFeeding(side: BreastSide, duration: TimeInterval) {
        focusedField = nil
        isLogging = true

        let entry = FeedingEntry(
            type: .breastFeeding,
            side: side,
            duration: duration,
            notes: notes.isEmpty ? nil : notes
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dataStore.addFeeding(entry)
            isLogging = false
            confirmationMessage = "Logged \(side.displayName) breast feeding for \(Int(duration/60)) minutes"
            showingConfirmation = true
            clearForm()
            selectedSide = dataStore.lastBreastSide
        }
    }

    private func logBottleFeeding() {
        guard let amountValue = Double(amount) else { return }

        focusedField = nil
        isLogging = true

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

        focusedField = nil
        isLogging = true

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
        focusedField = nil
    }

    // MARK: - Helpers

    private var hasFeedingHistory: Bool {
        return dataStore.entries.contains { entry in
            if case .feeding(let feedingEntry) = entry, feedingEntry.type == .breastFeeding {
                return true
            }
            return false
        }
    }

    private func oppositeOf(_ side: BreastSide) -> BreastSide {
        return side == .left ? .right : .left
    }
}

#Preview {
    FeedingView()
        .environmentObject(DataStore())
}
