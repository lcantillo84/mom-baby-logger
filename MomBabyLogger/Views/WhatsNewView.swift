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
                        Image(systemName: "sparkles")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                            .padding(.top, 20)

                        Text("What's New")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Version \(content.version)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 10)

                    // Title
                    Text(content.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // Features List
                    VStack(spacing: 20) {
                        ForEach(content.features) { feature in
                            FeatureRow(feature: feature)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    Spacer(minLength: 20)

                    // Continue Button
                    Button {
                        AppVersionManager.shared.markWhatsNewAsSeen()
                        dismiss()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
        }
        .interactiveDismissDisabled()
    }
}

struct FeatureRow: View {
    let feature: WhatsNewFeature

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            Image(systemName: feature.icon)
                .font(.system(size: 28))
                .foregroundColor(.blue)
                .frame(width: 50, height: 50)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)

                Text(feature.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
