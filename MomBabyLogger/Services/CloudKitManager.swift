//
//  CloudKitManager.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// FACADE over the v2 CKSyncEngine architecture (SYNC_AUDIT.md §8).
//
// The ~1200-line hand-rolled sync engine that used to live here (manual
// change tokens, push subscriptions, batching, retry queues, fingerprint
// diffing, timing-flag guards) was REPLACED on 2026-07-08 by:
//
//   Services/SyncEngine/SyncCoordinator.swift   — CKSyncEngine host
//   Services/SyncEngine/EntryChangeLedger.swift — explicit-event shadow ledger
//   Services/SyncEngine/EntryRecordCoding.swift — frozen record shape
//   Models/DataStore+SyncEngine.swift           — inbound upsert/delete
//
// This class keeps the EXACT public API the rest of the app already calls
// (MomBabyLoggerApp, PartnerSyncView, HistoryView, SharingManager), so no
// view or sharing code changed in the cutover. Everything delegates to
// SyncCoordinator. Do not add sync logic back here.
// ─────────────────────────────────────────────────────────────

import CloudKit
import Combine
import Foundation

// Shared CloudKit constants (referenced by SharingManager + SyncCoordinator).
let kContainerID = "iCloud.lilycantilloapp.mommysblog"
let kZoneName = "MommysLogZone"

// All `[CloudKit]` diagnostic logging goes through this.
// TEMPORARY (2026-07-07): forced ON in Release to diagnose/verify production
// two-phone sync. Revert `if true` back to `#if DEBUG` / `#endif` once the
// CKSyncEngine rollout is confirmed working on the App Store build.
private func ckLog(_ message: String) {
    if true {
        print(message)
    }
}

@MainActor
class CloudKitManager: ObservableObject {

    static let shared = CloudKitManager()

    private lazy var container = CKContainer(identifier: kContainerID)
    private lazy var sharedDB: CKDatabase = { container.sharedCloudDatabase }()

    private init() {}

    // ─── Boot paths ────────────────────────────────────────────────────────

    // Called once from MomBabyLoggerApp.onAppear. Restores participant state
    // (durable ground truth) exactly as before, then boots the sync engine.
    func configure(with dataStore: DataStore) {
        Task {
            if !SyncStateManager.shared.isPro {
                // Case 1: hasAcceptedShare is the durable ground truth for participants.
                if SyncStateManager.shared.hasAcceptedShare || SyncStateManager.shared.isParticipant {
                    SyncStateManager.shared.isParticipant = true
                    SyncStateManager.shared.activatePro()
                }
                // Case 2: reinstall — AppStorage is gone but the shared zone still
                // exists in iCloud; re-detect and restore participant + Pro.
                else if let sharedZones = try? await sharedDB.allRecordZones(), !sharedZones.isEmpty {
                    SyncStateManager.shared.isParticipant = true
                    SyncStateManager.shared.activatePro()
                }
            }
            guard SyncStateManager.shared.isPro else { return }
            ckLog("[CloudKit] configure: booting SyncCoordinator")
            SyncCoordinator.shared.start(dataStore: dataStore)
        }
    }

    // Called by the onChange(of: isPro) hook in MomBabyLoggerApp the moment Pro
    // flips ON (purchase, Restore Purchase, or launch entitlement resolving).
    func activateSync(with dataStore: DataStore) {
        ckLog("[CloudKit] activateSync: booting SyncCoordinator")
        SyncCoordinator.shared.start(dataStore: dataStore)
    }

    // Called by SharingManager after this phone accepts a share (role changed
    // to participant) and after an owner-side zone migration.
    func startSyncAfterJoining() {
        ckLog("[CloudKit] startSyncAfterJoining: restarting SyncCoordinator")
        SyncCoordinator.shared.restart()
    }

    // ─── Foreground / view hooks ───────────────────────────────────────────

    // Push pending local changes UP (entries logged just before backgrounding).
    func pushPendingChanges() async {
        await SyncCoordinator.shared.manualSend()
    }

    // Pull remote changes DOWN (foreground, silent push, view open, 60s-free now:
    // CKSyncEngine schedules its own fetches; this just keeps latency low).
    func fetchChanges() async {
        await SyncCoordinator.shared.manualFetch()
    }

    // Foreground entry point — same as fetchChanges under the v2 engine (the
    // engine's state serialization makes every fetch reliable; the old
    // token-clearing full-refetch hack is no longer needed).
    func fetchOnForeground() async {
        await SyncCoordinator.shared.manualFetch()
    }

    // ─── Recovery paths ────────────────────────────────────────────────────

    // Pull-to-refresh "hard" path (PartnerSyncView): throw away fetch state and
    // re-download everything. Idempotent — matching entries are no-ops.
    func clearSharedZoneTokens() {
        Task { await SyncCoordinator.shared.fullRefetch() }
    }

    // Same hard-refetch, kept as a separate name for its SharingManager call site.
    func forceRefetchAll() {
        Task { await SyncCoordinator.shared.fullRefetch() }
    }

    // DEBUG recovery hammer: re-enqueue every local entry as a save.
    func forceReuploadAll() {
        Task { await SyncCoordinator.shared.forceReuploadAll() }
    }

    // ─── Remote notification (called from AppDelegate) ─────────────────────

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        SyncCoordinator.shared.handleRemoteNotification(userInfo)
    }

    // ─── Partner Entry Tracking ────────────────────────────────────────────
    // Which entry UUIDs were logged by the other person (ActivityRowView badge).
    // Same UserDefaults table as always; now written by SyncCoordinator.

    func isPartnerEntry(_ id: UUID) -> Bool {
        SyncCoordinator.shared.isPartnerEntry(id)
    }
}
