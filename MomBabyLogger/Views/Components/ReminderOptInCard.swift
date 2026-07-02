//
//  ReminderOptInCard.swift
//  MomBabyLogger
//
// Shown in TodayView once the user has logged their first feeding, IF notification
// permission has never been requested. Surfaces feeding reminders — the app's
// single strongest retention tool — which were previously buried in Settings and
// never discovered by new users (reminders default to ON, but the app silently
// can't schedule them until iOS notification permission is granted).
//
// Tapping "Turn On Reminders" triggers the iOS permission prompt and, on grant,
// immediately schedules a reminder from the most recent feeding so the first one
// fires without waiting for the next log. Declining dismisses it for good (per device).
//
// Uses only public NotificationManager APIs — touches no model or sacred logic.

import SwiftUI

struct ReminderOptInCard: View {
    @EnvironmentObject var dataStore: DataStore
    @ObservedObject private var notifications = NotificationManager.shared

    @State private var dismissed = false
    @State private var requesting = false

    private let kDismissedKey = "mommyslog.reminderOptInDismissed"

    // Visible only when permission is still undetermined and the user hasn't
    // dismissed. Once granted or denied, authorizationStatus changes and the
    // card disappears automatically (NotificationManager is observed).
    private var isVisible: Bool {
        guard !dismissed,
              !UserDefaults.standard.bool(forKey: kDismissedKey) else { return false }
        return notifications.canRequestAuthorization
    }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.primaryAction.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.primaryAction)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Never miss a feeding")
                            .font(AppTheme.Typography.bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.Colors.primaryText)
                        Text("Get a gentle reminder when the next feeding is due")
                            .font(AppTheme.Typography.labelSmall)
                            .foregroundColor(AppTheme.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.Colors.tertiaryText)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await enableReminders() }
                } label: {
                    Group {
                        if requesting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Turn On Reminders")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(requesting)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.Colors.cardBackground)
            .cornerRadius(AppTheme.Radius.card)
            .modifier(CardShadow())
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                    .strokeBorder(AppTheme.Colors.primaryAction.opacity(0.20), lineWidth: 1)
            )
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func enableReminders() async {
        requesting = true
        defer { requesting = false }

        let granted = await NotificationManager.shared.requestAuthorization()
        if granted {
            // Feedings were logged before permission existed, so nothing was scheduled
            // yet. Schedule now from the most recent feeding so the first reminder fires
            // without waiting for the next log.
            let lastFeeding = dataStore.entries
                .compactMap { entry -> Date? in
                    if case .feeding(let f) = entry { return f.timestamp }
                    return nil
                }
                .max()
            if let lastFeeding {
                await NotificationManager.shared.scheduleReminder(
                    for: lastFeeding,
                    settings: ReminderSettings.load()
                )
            }
        } else {
            // Declined at the iOS prompt — don't nag again.
            dismiss()
        }
    }

    private func dismiss() {
        UserDefaults.standard.set(true, forKey: kDismissedKey)
        withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
    }
}

#Preview {
    VStack {
        ReminderOptInCard()
            .environmentObject(DataStore())
    }
    .padding(.vertical)
    .background(AppTheme.Colors.appBackground)
}
