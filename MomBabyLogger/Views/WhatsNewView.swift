//
//  WhatsNewView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/26/25.
//

import SwiftUI

struct WhatsNewView: View {
    let content: WhatsNewContent
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.Colors.primaryAction.opacity(0.12))
                                .frame(width: 90, height: 90)
                            Image(systemName: "sparkles")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(AppTheme.Colors.primaryAction)
                        }
                        .padding(.top, 20)

                        Text("What's New")
                            .font(AppTheme.Typography.titleMedium)
                            .foregroundColor(AppTheme.Colors.primaryText)

                        Text("Version \(content.version)")
                            .font(AppTheme.Typography.bodySmall)
                            .foregroundColor(AppTheme.Colors.secondaryText)
                    }
                    .padding(.bottom, 10)

                    Text(content.title)
                        .font(AppTheme.Typography.titleSmall)
                        .foregroundColor(AppTheme.Colors.primaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(spacing: 20) {
                        ForEach(content.features) { feature in
                            FeatureRow(feature: feature)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    Spacer(minLength: 20)

                    Button {
                        AppVersionManager.shared.markWhatsNewAsSeen()
                        dismiss()
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(AppTheme.Colors.appBackground.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .interactiveDismissDisabled()
    }
}

struct FeatureRow: View {
    let feature: WhatsNewFeature

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(AppTheme.Colors.primaryAction)
                .frame(width: 50, height: 50)
                .background(AppTheme.Colors.primaryAction.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(AppTheme.Typography.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.primaryText)

                Text(feature.description)
                    .font(AppTheme.Typography.bodySmall)
                    .foregroundColor(AppTheme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

#Preview {
    WhatsNewView(content: WhatsNewContent(
        version: "1.1.0",
        title: "Edit Your Logs Anytime!",
        features: [
            WhatsNewFeature(icon: "pencil.circle.fill", title: "Edit Entries", description: "Fix mistakes or update any feeding or diaper log"),
            WhatsNewFeature(icon: "hand.draw.fill", title: "Easy Swipe", description: "Swipe left on any entry to edit or delete"),
            WhatsNewFeature(icon: "clock.fill", title: "Update Details", description: "Change times, amounts, notes, and more")
        ]
    ))
}
