//
//  StatsCardView.swift
//  MomBabyLogger
//

import SwiftUI

struct StatsCardView: View {
    let icon: String
    let title: String
    let count: Int
    let subtitle: String?
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Rectangle()
                .frame(height: 3)
                .foregroundColor(color)
                .cornerRadius(AppTheme.Radius.sm)

            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(color)

            Text("\(count)")
                .font(AppTheme.Typography.displayMedium)
                .foregroundColor(color)

            Text(title)
                .font(AppTheme.Typography.bodyMedium)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .background(color.opacity(0.10))
        .cornerRadius(AppTheme.Radius.card)
        .modifier(CardShadow())
    }
}

#Preview {
    VStack(spacing: 16) {
        StatsCardView(
            icon: "heart.fill",
            title: "Breast",
            count: 8,
            subtitle: "120 min",
            color: AppTheme.Colors.breastFeeding
        )
        StatsCardView(
            icon: "drop.fill",
            title: "Wet",
            count: 6,
            subtitle: nil,
            color: AppTheme.Colors.wetDiaper
        )
    }
    .padding()
    .background(AppTheme.Colors.appBackground)
}
