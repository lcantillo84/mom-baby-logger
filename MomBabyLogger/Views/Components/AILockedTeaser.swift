//
//  AILockedTeaser.swift
//  MomBabyLogger
//

import SwiftUI

// Shown on TodayView for free users in place of AIPredictionCard.
// Tapping it opens ProGateView so users can upgrade.
struct AILockedTeaser: View {
    var onUnlockTap: () -> Void

    var body: some View {
        Button(action: onUnlockTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.primaryAction.opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: "brain")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppTheme.Colors.primaryAction)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("AI Patterns")
                            .font(AppTheme.Typography.bodyLarge)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.Colors.primaryText)

                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.Colors.primaryAction)
                    }

                    Text("Next feeding prediction & anomaly alerts")
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundColor(AppTheme.Colors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(AppTheme.Colors.tertiaryText)
            }
            .padding()
            .background(AppTheme.Colors.primaryAction.opacity(0.06))
            .cornerRadius(AppTheme.Radius.card)
            .modifier(CardShadow())
            .padding(.horizontal)
        }
    }
}

#Preview {
    AILockedTeaser(onUnlockTap: {})
        .background(AppTheme.Colors.appBackground)
}
