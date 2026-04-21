//
//  ProGateView.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// This is the "paywall" screen — what non-Pro users see when they
// tap "Partner Sync" in Settings.
//
// It shows:
//  • What they get by upgrading (the value proposition)
//  • A big "Upgrade to Pro" button
//  • A "Restore Purchase" link for people who already paid
//
// When the user taps Upgrade, this will trigger StoreKit to show
// the purchase sheet (StoreKit integration will come in Session 5).
// For now the button sets isPro = true directly so you can test
// the rest of the flow.
// ─────────────────────────────────────────────────────────────

import SwiftUI

struct ProGateView: View {

    // 📖 SWIFT CONCEPT: @ObservedObject
    // SyncStateManager.shared is the same object everywhere in the app.
    // @ObservedObject tells SwiftUI "watch this; redraw me if isPro changes."
    @ObservedObject private var sync = SyncStateManager.shared

    @Environment(\.dismiss) private var dismiss

    // The features list — easy to update without touching layout code.
    private let features: [(icon: String, title: String, detail: String)] = [
        ("person.2.fill",        "Partner & Nanny Sync",   "Share live logs with anyone helping with baby"),
        ("icloud.fill",          "iCloud Backup",          "Baby's data is safe even if you lose your phone"),
        ("arrow.clockwise",      "Sync History",           "Entries appear on all your devices instantly"),
        ("lock.shield.fill",     "Private & Encrypted",    "Data lives in your iCloud — we never see it"),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {

                    // ── Hero ──────────────────────────────────────────────
                    heroSection

                    // ── Features ─────────────────────────────────────────
                    featuresSection
                        .padding(.top, 32)

                    // ── Pricing ──────────────────────────────────────────
                    pricingSection
                        .padding(.top, 32)

                    // ── Actions ──────────────────────────────────────────
                    actionsSection
                        .padding(.top, 24)
                        .padding(.bottom, 40)
                }
                .padding(.horizontal, 24)
            }
            .background(AppTheme.Colors.appBackground.ignoresSafeArea())
            .navigationTitle("Mommy's Log Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(AppTheme.Colors.primaryAction)
                }
            }
        }
    }

    // MARK: - Sections

    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.primaryAction.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }
            .padding(.top, 32)

            Text("Sync with your partner")
                .font(AppTheme.Typography.titleLarge)
                .foregroundColor(AppTheme.Colors.primaryText)
                .multilineTextAlignment(.center)

            Text("Both parents see every feeding and diaper change in real time — no setup, no servers, just iCloud.")
                .font(AppTheme.Typography.bodyMedium)
                .foregroundColor(AppTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
    }

    private var featuresSection: some View {
        VStack(spacing: 12) {
            ForEach(features, id: \.title) { feature in
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppTheme.Colors.primaryAction.opacity(0.10))
                            .frame(width: 44, height: 44)
                        Image(systemName: feature.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(AppTheme.Colors.primaryAction)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(AppTheme.Typography.bodyLarge)
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.Colors.primaryText)
                        Text(feature.detail)
                            .font(AppTheme.Typography.labelSmall)
                            .foregroundColor(AppTheme.Colors.secondaryText)
                    }
                    Spacer()
                }
                .padding(16)
                .background(AppTheme.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
            }
        }
    }

    private var pricingSection: some View {
        VStack(spacing: 8) {
            Text("$2.99 / month")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.Colors.primaryText)
            Text("Cancel anytime • 7-day free trial")
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.tertiaryText)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.primaryAction.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // 📖 SWIFT CONCEPT: Button with action closure
            // The { } after Button is the "what to do when tapped" block.
            // We call activatePro() here. In production this will launch StoreKit.
            Button {
                // TODO Session 5: Replace with StoreKit purchase flow
                // For now: instantly grant Pro so you can test sync features.
                SyncStateManager.shared.activatePro()
                dismiss()
            } label: {
                Text("Start Free Trial")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                // TODO Session 5: StoreKit restore purchases
                SyncStateManager.shared.activatePro()
                dismiss()
            } label: {
                Text("Restore Purchase")
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }

            Text("Privacy Policy • Terms of Service")
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.tertiaryText)
        }
    }
}

#Preview {
    ProGateView()
}
