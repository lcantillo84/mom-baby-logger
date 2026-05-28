//
//  DiaperView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct DiaperView: View {
    @EnvironmentObject var dataStore: DataStore
    @ObservedObject private var sync = SyncStateManager.shared
    @State private var notes: String = ""
    @State private var showingConfirmation = false
    @State private var lastLoggedType: ActivityType?
    @State private var isLogging = false
    @State private var confirmationMessage: String = ""
    @FocusState private var focusedField: FocusField?
    @State private var showingPartnerSync = false
    @State private var showingProGate = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text("What type of diaper change?")
                        .font(AppTheme.Typography.titleMedium)
                        .foregroundColor(AppTheme.Colors.primaryText)
                        .padding(.top)

                    VStack(spacing: 16) {
                        diaperButton(
                            type: .wetDiaper,
                            icon: "drop.triangle",
                            color: AppTheme.Colors.wetDiaper,
                            title: "Wet"
                        )
                        diaperButton(
                            type: .poopDiaper,
                            icon: "leaf.fill",
                            color: AppTheme.Colors.poopDiaper,
                            title: "Poop"
                        )
                        diaperButton(
                            type: .mixedDiaper,
                            icon: "drop.triangle.fill",
                            color: AppTheme.Colors.mixedDiaper,
                            title: "Both"
                        )
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(AppTheme.Typography.sectionHeader)
                            .foregroundColor(AppTheme.Colors.secondaryText)

                        TextEditor(text: $notes)
                            .frame(height: 100)
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
            .navigationTitle("Diaper Change")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.Colors.appBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    partnerSyncButton
                }
            }
            .navigationDestination(isPresented: $showingPartnerSync) {
                PartnerSyncView().environmentObject(dataStore)
            }
            .keyboardDoneButton(focusedField: $focusedField)
            .alert("Success!", isPresented: $showingConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(confirmationMessage)
            }
            .overlay {
                if isLogging {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppTheme.Colors.primaryAction))
                                .scaleEffect(1.5)

                            Text("Logging...")
                                .foregroundColor(AppTheme.Colors.primaryText)
                                .font(AppTheme.Typography.bodyMedium)
                                .fontWeight(.medium)
                        }
                        .padding(32)
                        .background(AppTheme.Colors.cardBackground)
                        .cornerRadius(AppTheme.Radius.xl)
                        .modifier(CardShadow())
                    }
                }
            }
        }
        .sheet(isPresented: $showingProGate) {
            ProGateView()
        }
    }

    // MARK: - Diaper Button

    private func diaperButton(type: ActivityType, icon: String, color: Color, title: String) -> some View {
        Button(action: {
            logDiaperChange(type: type)
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(color)
                    .clipShape(Circle())
                    .modifier(CardShadow())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppTheme.Typography.titleSmall)
                        .foregroundColor(AppTheme.Colors.primaryText)

                    Text("Tap to log")
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundColor(AppTheme.Colors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.Colors.tertiaryText)
            }
            .padding(AppTheme.Spacing.md)
            .background(color.opacity(0.10))
            .cornerRadius(AppTheme.Radius.card)
            .modifier(CardShadow())
        }
        .buttonStyle(DiaperCardButtonStyle())
    }

    // MARK: - Logging Function

    private func logDiaperChange(type: ActivityType) {
        guard !isLogging else { return }

        focusedField = nil
        isLogging = true
        lastLoggedType = type

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let entry = DiaperEntry(
                type: type,
                notes: notes.isEmpty ? nil : notes
            )
            dataStore.addDiaper(entry)

            isLogging = false
            confirmationMessage = "\(type.displayName) has been successfully recorded"
            showingConfirmation = true
            notes = ""
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

}

#Preview {
    DiaperView()
        .environmentObject(DataStore())
}
