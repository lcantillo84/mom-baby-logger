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
//  • ONE price: a one-time Lifetime Unlock ($14.99)
//  • A big "Unlock Forever" button (real StoreKit purchase)
//  • A "Restore Purchase" link for people who already paid
// ─────────────────────────────────────────────────────────────

import SwiftUI
import StoreKit
import Observation

// ─────────────────────────────────────────────────────────────
// Plan — product IDs that grant Pro.
//
// 2026-09-25: the paywall sells ONE thing — the Lifetime unlock.
// Baby tracking is a FINITE need (roughly 12–18 months), so a
// subscription is the wrong fit. Monthly/Yearly are no longer
// OFFERED, but they stay in this enum so anyone who already bought
// them is still recognized by applyEntitlementState() / restore().
// ─────────────────────────────────────────────────────────────
enum ProPlan: String, CaseIterable, Identifiable {
    case lifetime = "lilycantilloapp.mommysblog.pro.lifetime"
    case yearly   = "lilycantilloapp.mommysblog.pro.yearly"    // legacy — not offered
    // legacy — not offered. This is the REAL App Store Connect ID of the original
    // monthly subscription (1.6.0–1.7.1 asked for ".pro.monthly", which never existed).
    case monthly  = "lilycantilloapp.mommysblog.subscription.pro"

    var id: String { rawValue }

    /// Shown only if the real App Store price can't load. Keep in sync with ASC.
    static let lifetimeFallbackPrice = "$14.99"
}

// ─────────────────────────────────────────────────────────────
// SubscriptionManager — handles all real App Store payments.
// Uses @Observable (iOS 17+) which avoids ObservableObject issues.
// ─────────────────────────────────────────────────────────────
@MainActor
@Observable
class SubscriptionManager {

    static let shared = SubscriptionManager()
    private let productIDs = Set(ProPlan.allCases.map(\.rawValue))

    /// Loaded App Store products, keyed by product ID.
    var products: [String: Product] = [:]
    var isLoadingProducts: Bool = false
    var isPurchasing: Bool = false
    var errorMessage: String?

    private var transactionListenerTask: Task<Void, Never>?
    private init() {}

    func product(for plan: ProPlan) -> Product? { products[plan.rawValue] }

    /// True when Pro was unlocked by joining a partner's share rather than by
    /// paying. Never revoke Pro from those users based on StoreKit — they have
    /// no transaction of their own and never will.
    private var isPartnerGrantedPro: Bool {
        SyncStateManager.shared.isParticipant || SyncStateManager.shared.hasAcceptedShare
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: productIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            errorMessage = nil
        } catch {
            errorMessage = "Could not load pricing. Check your internet connection."
        }
    }

    func purchase(_ plan: ProPlan) async -> Bool {
        // Hard lock: the app sells ONLY the one-time Lifetime unlock. Subscriptions
        // can never be started from this build, even if a caller passes one by mistake.
        guard plan == .lifetime else { return false }

        // The product may not have loaded yet (slow network, first launch) —
        // try once more before telling the user anything failed.
        if product(for: plan) == nil {
            await loadProducts()
        }
        guard let product = product(for: plan) else {
            errorMessage = "The App Store isn't responding right now. Please try again in a minute."
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

        var restored = await hasValidEntitlement()
        if !restored {
            try? await AppStore.sync()
            restored = await hasValidEntitlement()
        }

        if restored {
            SyncStateManager.shared.activatePro()
        } else {
            errorMessage = "No previous purchase found for this Apple ID."
        }
    }

    func startTransactionListener() {
        transactionListenerTask?.cancel()
        transactionListenerTask = Task(priority: .background) {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result,
                      self.productIDs.contains(transaction.productID)
                else { continue }
                await transaction.finish()
                // Re-evaluate ALL entitlements rather than trusting this one
                // transaction: a lapsed monthly must not revoke a Lifetime unlock.
                await self.applyEntitlementState()
            }
        }
    }

    // Called once on every app launch to silently restore Pro for users
    // who reinstalled, switched phones, or whose subscription renewed overnight.
    func checkCurrentEntitlements() async {
        await applyEntitlementState()
    }

    /// Scans every current entitlement across all three products and decides
    /// Pro state ONCE. Any single valid purchase grants Pro.
    private func applyEntitlementState() async {
        var sawOurTransaction = false
        var entitled = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  productIDs.contains(transaction.productID)
            else { continue }
            sawOurTransaction = true

            let isRevoked = transaction.revocationDate != nil
            // Non-consumables (Lifetime) have no expirationDate — never expire.
            let isExpired = transaction.expirationDate.map { $0 < Date() } ?? false
            if !isRevoked && !isExpired {
                entitled = true
                break
            }
        }

        if entitled {
            SyncStateManager.shared.activatePro()
        } else if sawOurTransaction && !isPartnerGrantedPro {
            // Only revoke on POSITIVE evidence of a dead purchase. If the store
            // returned nothing at all (offline, slow first launch) leave state
            // alone so Pro doesn't flicker off for a paying user.
            SyncStateManager.shared.deactivatePro()
        }
    }

    private func hasValidEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil
            else { continue }
            let isExpired = transaction.expirationDate.map { $0 < Date() } ?? false
            if !isExpired { return true }
        }
        return false
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

    // The only plan the paywall sells.
    private let offeredPlan: ProPlan = .lifetime

    // The features list — easy to update without touching layout code.
    private let features: [(icon: String, title: String, detail: String)] = [
        ("person.2.fill",        "Partner & Nanny Sync",   "Share live logs with anyone helping with baby"),
        ("chart.bar.fill",       "Daily Insights",         "Time since last feeding, trends & daily averages"),
        ("calendar.badge.clock", "Weekly Charts",          "7-day feeding and diaper charts at a glance"),
        ("icloud.fill",          "iCloud Sync",            "Your logs are saved to your own iCloud"),
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

            Text("Both parents see every feeding and diaper change within moments — no setup, no servers, just iCloud.")
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
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Lifetime Unlock")
                    .font(AppTheme.Typography.bodyLarge)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.Colors.primaryText)
                Text("One payment. Yours for every baby.")
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.secondaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                if let product = subscriptions.product(for: offeredPlan) {
                    Text(product.displayPrice)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.Colors.primaryText)
                } else if subscriptions.isLoadingProducts {
                    ProgressView()
                } else {
                    Text(ProPlan.lifetimeFallbackPrice)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(AppTheme.Colors.primaryText)
                }
                Text("one time")
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.tertiaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.primaryAction.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.card)
                .stroke(AppTheme.Colors.primaryAction, lineWidth: 2)
        )
        .task { await subscriptions.loadProducts() }
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
                    let success = await subscriptions.purchase(offeredPlan)
                    if success { dismiss() }
                }
            } label: {
                if subscriptions.isPurchasing || subscriptions.isLoadingProducts {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Unlock Forever")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(subscriptions.isPurchasing || subscriptions.isLoadingProducts)

            Text("One payment · no subscription · restores on all your devices")
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.tertiaryText)
                .multilineTextAlignment(.center)

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
