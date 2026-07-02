//
//  UpgradeNudgeBanner.swift
//  MomBabyLogger
//
// Shown in TodayView once the user has logged 5+ entries but hasn't upgraded.
// Dismisses for 7 days so it doesn't feel spammy.
// Tapping anywhere opens ProGateView.

import SwiftUI

struct UpgradeNudgeBanner: View {

    var onTap: () -> Void

    @State private var dismissed = false

    private let kDismissedUntilKey = "mommyslog.nudgeDismissedUntil"

    private var isVisible: Bool {
        guard !dismissed else { return false }
        let until = UserDefaults.standard.double(forKey: kDismissedUntilKey)
        return Date().timeIntervalSince1970 > until
    }

    var body: some View {
        if isVisible {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Colors.primaryAction.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.primaryAction)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're on a roll — try Pro free")
                            .font(AppTheme.Typography.bodyMedium)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.Colors.primaryText)
                        Text("AI predictions, partner sync & charts — 7 days free")
                            .font(AppTheme.Typography.labelSmall)
                            .foregroundColor(AppTheme.Colors.secondaryText)
                    }

                    Spacer()

                    Button {
                        snooze()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.Colors.tertiaryText)
                            .padding(8)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .background(AppTheme.Colors.cardBackground)
                .cornerRadius(AppTheme.Radius.card)
                .modifier(CardShadow())
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                        .strokeBorder(AppTheme.Colors.primaryAction.opacity(0.20), lineWidth: 1)
                )
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func snooze() {
        let sevenDays = Date().timeIntervalSince1970 + (7 * 24 * 3600)
        UserDefaults.standard.set(sevenDays, forKey: kDismissedUntilKey)
        withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
    }
}

#Preview {
    VStack {
        UpgradeNudgeBanner(onTap: {})
    }
    .padding(.vertical)
    .background(AppTheme.Colors.appBackground)
}
