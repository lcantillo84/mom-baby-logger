//
//  StatsCardView.swift
//  MomBabyLogger
//
//  Reusable stats card component
//

import SwiftUI

struct StatsCardView: View {
    let icon: String           // SF Symbol name
    let title: String          // e.g., "Breast Feedings"
    let count: Int             // Main number
    let subtitle: String?      // e.g., "120 min total"
    let color: Color           // Theme color for the card

    var body: some View {
        VStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)

            // Count
            Text("\(count)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            // Title
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Subtitle (if provided)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

#Preview {
    VStack(spacing: 16) {
        StatsCardView(
            icon: "heart.fill",
            title: "Breast Feedings",
            count: 8,
            subtitle: "120 min total",
            color: .pink
        )

        StatsCardView(
            icon: "drop.fill",
            title: "Wet Diapers",
            count: 6,
            subtitle: nil,
            color: .blue
        )
    }
    .padding()
}
