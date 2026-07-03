//
//  WidgetTipCard.swift
//  MomBabyLogger
//
// Shown in TodayView once the user has logged a feeding: tells them the home-screen
// widget exists and how to add it. iOS never auto-places a widget and most users don't
// know how to add one, so without this nudge the widget (a key retention feature) goes
// unused. Dismisses for good, per device. Touches no model or sacred logic — pure UI.

import SwiftUI

struct WidgetTipCard: View {
    @State private var dismissed = false

    private let kDismissedKey = "mommyslog.widgetTipDismissed"

    private var isVisible: Bool {
        !dismissed && !UserDefaults.standard.bool(forKey: kDismissedKey)
    }

    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.primaryAction.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "apps.iphone")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.primaryAction)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add the home screen widget")
                            .font(AppTheme.Typography.bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.Colors.primaryText)
                        Text("See the last feeding without opening the app")
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

                VStack(alignment: .leading, spacing: 6) {
                    tipStep("1", "Touch and hold your home screen")
                    tipStep("2", "Tap the + in the top-left corner")
                    tipStep("3", "Search \u{201C}Mommy\u{2019}s Log\u{201D} and add it")
                }
                .padding(.top, 2)

                Button {
                    dismiss()
                } label: {
                    Text("Got it")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, AppTheme.Spacing.xs)
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

    private func tipStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.Colors.primaryAction)
                .frame(width: 20, height: 20)
                .background(AppTheme.Colors.primaryAction.opacity(0.12))
                .clipShape(Circle())
            Text(text)
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dismiss() {
        UserDefaults.standard.set(true, forKey: kDismissedKey)
        withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
    }
}

#Preview {
    VStack {
        WidgetTipCard()
    }
    .padding(.vertical)
    .background(AppTheme.Colors.appBackground)
}
