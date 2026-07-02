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
import StoreKit
import Observation

// ─────────────────────────────────────────────────────────────
// SubscriptionManager — handles all real App Store payments.
// Uses @Observable (iOS 17+) which avoids ObservableObject issues.
// ─────────────────────────────────────────────────────────────
@MainActor
@Observable
class SubscriptionManager {

    static let shared = SubscriptionManager()
    private let productID = "lilycantilloapp.mommysblog.pro.monthly"

    var product: Product?
    var isPurchasing: Bool = false
    var errorMessage: String?

    private var transactionListenerTask: Task<Void, Never>?
    private init() {}

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [productID])
            product = products.first
        } catch {
            errorMessage = "Could not load subscription details. Check your internet connection."
        }
    }

    func purchase() async -> Bool {
        guard let product else {
            errorMessage = "Product not loaded yet. Please try again."
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                SyncStateManager.shared.activatePro()
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                errorMessage = "Purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        errorMessage = nil
        var restored = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productID,
               transaction.revocationDate == nil {
                SyncStateManager.shared.activatePro()
                restored = true
                break
            }
        }
        if !restored {
            try? await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                   transaction.productID == productID,
                   transaction.revocationDate == nil {
                    SyncStateManager.shared.activatePro()
                    restored = true
                    break
                }
            }
        }
        if !restored {
            errorMessage = "No active subscription found for this Apple ID."
        }
    }

    func startTransactionListener() {
        transactionListenerTask?.cancel()
        transactionListenerTask = Task(priority: .background) {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result,
                      transaction.productID == self.productID
                else { continue }
                if transaction.revocationDate != nil {
                    SyncStateManager.shared.deactivatePro()
                } else if let expiration = transaction.expirationDate, expiration < Date() {
                    SyncStateManager.shared.deactivatePro()
                } else {
                    SyncStateManager.shared.activatePro()
                }
                await transaction.finish()
            }
        }
    }

    // Called once on every app launch to silently restore Pro for users
    // who reinstalled, switched phones, or whose subscription renewed overnight.
    func checkCurrentEntitlements() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == productID,
                  transaction.revocationDate == nil
            else { continue }
            let isExpired = transaction.expirationDate.map { $0 < Date() } ?? false
            if isExpired {
                SyncStateManager.shared.deactivatePro()
            } else {
                SyncStateManager.shared.activatePro()
            }
            return
        }
        // No active entitlement found — only deactivate if they weren't already marked Pro
        // (avoids flickering on first launch before store responds)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let value): return value
        }
    }
}

private enum StoreError: LocalizedError {
    case failedVerification
    var errorDescription: String? { "Transaction verification failed. Please contact support." }
}

struct ProGateView: View {

    @ObservedObject private var sync = SyncStateManager.shared
    private let subscriptions = SubscriptionManager.shared

    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage: String?

    // The features list — easy to update without touching layout code.
    private let features: [(icon: String, title: String, detail: String)] = [
        ("person.2.fill",        "Partner & Nanny Sync",   "Share live logs with anyone helping with baby"),
        ("brain",                "AI Insights",            "Next-feeding predictions & anomaly alerts"),
        ("chart.bar.fill",       "Daily Insights",         "Time since last feeding, trends & daily averages"),
        ("calendar.badge.clock", "Weekly Charts",          "7-day feeding and diaper charts at a glance"),
        ("icloud.fill",          "iCloud Backup",          "Baby's data is safe even if you lose your phone"),
        ("lock.shield.fill",     "Private & Encrypted",    "Data lives in your iCloud — we never see it"),
    ]

    var body: some View {
        NavigationStack {
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
            // Show the real App Store price when loaded, fallback to hardcoded price
            Text(subscriptions.product.map { "\($0.displayPrice) / month" } ?? "$2.99 / month")
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
        .task { await subscriptions.loadProduct() }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if let error = subscriptions.errorMessage ?? errorMessage {
                Text(error)
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.destructiveAction)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    let success = await subscriptions.purchase()
                    if success { dismiss() }
                }
            } label: {
                if subscriptions.isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Start Free Trial")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(subscriptions.isPurchasing)

            Button {
                Task {
                    await subscriptions.restore()
                    if SyncStateManager.shared.isPro { dismiss() }
                }
            } label: {
                if subscriptions.isPurchasing {
                    ProgressView()
                        .tint(AppTheme.Colors.primaryAction)
                } else {
                    Text("Restore Purchase")
                        .font(AppTheme.Typography.bodyMedium)
                        .foregroundColor(AppTheme.Colors.primaryAction)
                }
            }
            .disabled(subscriptions.isPurchasing)

            HStack(spacing: 4) {
                Link("Privacy Policy", destination: URL(string: "https://lcantillo84.github.io/mom-baby-logger/privacy-policy.html")!)
                Text("•")
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(AppTheme.Typography.labelSmall)
            .foregroundColor(AppTheme.Colors.primaryAction)
        }
    }
}

#Preview {
    ProGateView()
}
