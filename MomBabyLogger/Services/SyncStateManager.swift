//
//  SyncStateManager.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// This is a tiny "dashboard" that tracks two things:
//   1. Is the user a Pro subscriber? (isPro)
//   2. What is the current sync status? (syncing / synced / error)
//
// Every view in the app that needs to show a sync badge or a Pro
// gate reads from this single object. CloudKitManager writes to it.
//
// Think of it like a status light on a router — other parts of the
// app look at this light to know if the internet (CloudKit) is working.
// ─────────────────────────────────────────────────────────────

import Combine
import Foundation
import SwiftUI

// 📖 SWIFT CONCEPT: @MainActor
// CloudKit and networking happen on background threads.
// @MainActor means "all changes to this object must happen on the main thread."
// SwiftUI requires UI updates on the main thread, so this keeps us safe automatically.
@MainActor
class SyncStateManager: ObservableObject {

    // 📖 SWIFT CONCEPT: Singleton
    // `static let shared` means there is ONE SyncStateManager for the whole app.
    // Every file that needs it writes: SyncStateManager.shared.someProperty
    // No need to pass it around as a parameter — it lives globally.
    static let shared = SyncStateManager()

    // 📖 SWIFT CONCEPT: @Published
    // When this property changes, every SwiftUI View that reads it will
    // automatically redraw. It's like a live TV feed — views are always current.
    @Published var syncStatus: SyncStatus = .notEnabled
    @Published var isPartnerConnected: Bool = false
    @Published var lastSyncedDate: Date? = nil

    // 📖 SWIFT CONCEPT: @AppStorage
    // This is UserDefaults but with a SwiftUI-friendly wrapper.
    // The value is saved to disk automatically — it survives app restarts.
    // Key "isPro" is the UserDefaults key where the Bool is stored.
    @AppStorage("mommyslog.isPro") var isPro: Bool = false
    @AppStorage("mommyslog.hasPartnerShare") var hasPartnerShare: Bool = false
    // true on the partner/nanny device — they accepted a share instead of creating one
    @AppStorage("mommyslog.isParticipant") var isParticipant: Bool = false

    // Raw UserDefaults — intentionally NOT @AppStorage so CloudKitManager never resets it.
    // Set true when CKAcceptSharesOperation succeeds; cleared only when user taps "Leave".
    var hasAcceptedShare: Bool {
        get { UserDefaults.standard.bool(forKey: "mommyslog.hasAcceptedShare") }
        set { UserDefaults.standard.set(newValue, forKey: "mommyslog.hasAcceptedShare") }
    }

    // The possible states sync can be in.
    // 📖 SWIFT CONCEPT: Enum with Associated Values
    // .error(String) carries extra info — the error message.
    // Compare: .error("No internet") vs plain .error without a message.
    enum SyncStatus: Equatable {
        case notEnabled           // user has not subscribed to Pro
        case idle                 // Pro is on but nothing is happening right now
        case syncing              // currently uploading or downloading
        case synced               // everything is up to date ✓
        case error(String)        // something went wrong; the String explains what

        // Human-readable label for the UI
        var label: String {
            switch self {
            case .notEnabled:  return "Sync not enabled"
            case .idle:        return "Sync ready"
            case .syncing:     return "Syncing..."
            case .synced:      return "Up to date"
            case .error:       return "Sync error"
            }
        }

        // Icon to show next to the label
        var iconName: String {
            switch self {
            case .notEnabled:  return "icloud.slash"
            case .idle:        return "icloud"
            case .syncing:     return "arrow.clockwise.icloud"
            case .synced:      return "checkmark.icloud"
            case .error:       return "exclamationmark.icloud"
            }
        }

        // Color for the icon
        var color: Color {
            switch self {
            case .notEnabled:  return AppTheme.Colors.tertiaryText
            case .idle:        return AppTheme.Colors.secondaryText
            case .syncing:     return AppTheme.Colors.primaryAction
            case .synced:      return AppTheme.Colors.primaryAction
            case .error:       return AppTheme.Colors.destructiveAction
            }
        }
    }

    // Private init enforces the singleton pattern — nothing outside can create a second one
    private init() {}

    // ─── Helper methods called by CloudKitManager ───

    func markSyncing() { syncStatus = .syncing }
    func markSynced()  { syncStatus = .synced; lastSyncedDate = Date() }
    func markIdle()    { syncStatus = isPro ? .idle : .notEnabled }

    func markError(_ message: String) {
        syncStatus = .error(message)
        // Auto-clear the error after 8 seconds so the UI doesn't stay red forever
        Task {
            try? await Task.sleep(for: .seconds(8))
            if case .error = self.syncStatus {
                self.syncStatus = isPro ? .idle : .notEnabled
            }
        }
    }

    // Called when Pro status is purchased or restored
    func activatePro() {
        isPro = true
        syncStatus = .idle
    }

    // Called if subscription lapses
    func deactivatePro() {
        isPro = false
        syncStatus = .notEnabled
    }
}