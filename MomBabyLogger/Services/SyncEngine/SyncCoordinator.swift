//
//  SyncCoordinator.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// CKSyncEngine HOST — the v2 sync engine (SYNC_AUDIT.md §8).
//
// Replaces the hand-rolled transport in the old CloudKitManager: change
// tokens, push subscriptions, batching, retries, backoff, and scheduling
// are all owned by Apple's CKSyncEngine. This class has exactly two jobs:
//
//   OUTBOUND: EntryChangeLedger.diff() emits EXPLICIT create/edit/delete
//             events → enqueued as pendingRecordZoneChanges.
//   INBOUND:  fetched changes are recorded in the ledger FIRST, then applied
//             to DataStore via applyInboundUpserts/Deletes (upsert-in-place —
//             no delete+re-add hack, no timing flags).
//
// ROLES — one engine at a time:
//   owner       → privateCloudDatabase, zone MommysLogZone (this device created it)
//   participant → sharedCloudDatabase, zone discovered via fetchedDatabaseChanges
// Separate persisted state serializations per database so role flips never
// corrupt each other. NEVER run this engine and the legacy engine together —
// both would apply the same inbound changes (duplicate risk).
//
// CONFLICTS: last-writer-wins on the record's `modifiedAt` field (stamped at
// local event-capture time). ⚠️ `modifiedAt` must exist in the PRODUCTION
// CloudKit schema before shipping (Console → Deploy Schema Changes to Production).
// ─────────────────────────────────────────────────────────────

import CloudKit
import Combine
import Foundation

// Same Release-forced logging policy as ckLog during rollout; revert the
// `if true` to `#if DEBUG`/`#endif` once two-phone sync is confirmed in prod.
private func seLog(_ message: String) {
    if true {
        print("[SyncEngine] \(message)")
    }
}

@MainActor
final class SyncCoordinator {

    static let shared = SyncCoordinator()

    enum Role: String {
        case owner
        case participant
    }

    // ─── State ─────────────────────────────────────────────────────────────

    private var engine: CKSyncEngine?
    private var role: Role?
    private weak var dataStore: DataStore?
    private let ledger = EntryChangeLedger()
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private lazy var container = CKContainer(identifier: kContainerID)

    // Participant's discovered shared zone (persisted across launches).
    private let kParticipantZoneKey = "mommyslog.syncEngine.participantZoneID"
    // Engine state serializations — one per database, never shared.
    private let kStatePrivateKey = "mommyslog.syncEngine.state.private"
    private let kStateSharedKey  = "mommyslog.syncEngine.state.shared"
    // One-shot migration + zone-save flags.
    private let kMigratedKey  = "mommyslog.syncEngine.v2.migrated"
    private let kZoneSavedKey = "mommyslog.syncEngine.zoneSaved"
    // Changes captured before the participant's zone is known (persisted).
    private let kHeldSavesKey   = "mommyslog.syncEngine.heldSaves"
    private let kHeldDeletesKey = "mommyslog.syncEngine.heldDeletes"
    // Partner-badge table — SAME key the app has always used (ActivityRowView reads it).
    private let kPartnerEntryIDsKey = "mommyslog.partnerEntryIDs"

    private init() {}

    // ─── Public API (called via the CloudKitManager facade) ────────────────

    /// Boot the engine. Idempotent — safe to call from configure(), the
    /// Pro-activation hook, and startSyncAfterJoining without double-booting.
    func start(dataStore: DataStore) {
        self.dataStore = dataStore
        guard SyncStateManager.shared.isPro else { return }
        guard !started else { return }
        started = true
        Task {
            await migrateIfNeeded()
            buildEngine(for: derivedRole())
            observeDataStore(dataStore)
            await scheduleDiff()
            SyncStateManager.shared.markIdle()
            await resetPartnerTagsIfNeeded()
        }
    }

    // One-shot (2026-07-08): the LEGACY engine guessed "from partner" via uploadedIDs
    // inference and mis-tagged some of the owner's own logs — those stale IDs still
    // sit in the persisted badge table. Wipe it once and do a full refetch so the
    // table rebuilds purely from CloudKit's creatorUserRecordID (server truth,
    // can't be wrong). Separate key from v2.migrated because devices that already
    // migrated before this fix landed still need the reset.
    private func resetPartnerTagsIfNeeded() async {
        let key = "mommyslog.partnerTagsResetV2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.removeObject(forKey: kPartnerEntryIDsKey)
        seLog("resetPartnerTagsIfNeeded: cleared legacy badge table — rebuilding from creatorUserRecordID")
        await fullRefetch()
    }

    /// Role transition (share accepted / left / revoked): tear down and rebuild.
    func restart() {
        guard let ds = dataStore else { return }
        seLog("restart: tearing down engine (role was \(role?.rawValue ?? "nil"))")
        cancellables.removeAll()
        engine = nil
        role = nil
        started = false
        start(dataStore: ds)
    }

    /// Push any locally-pending changes up now (foreground / view-open hook).
    func manualSend() async {
        await reconcileRoleIfNeeded()
        await scheduleDiff()
        try? await engine?.sendChanges()
    }

    /// Pull remote changes now (foreground / push / pull-to-refresh hook).
    func manualFetch() async {
        await reconcileRoleIfNeeded()
        try? await engine?.fetchChanges()
    }

    /// Pull-to-refresh "hard" path: throw away the engine's fetch state for the
    /// current database and re-download everything. Safe: inbound upserts are
    /// idempotent against the ledger (matching fingerprints are no-ops).
    func fullRefetch() async {
        guard let currentRole = role else { return }
        seLog("fullRefetch: resetting engine state for \(currentRole.rawValue)")
        UserDefaults.standard.removeObject(forKey: stateKey(for: currentRole))
        buildEngine(for: currentRole)
        try? await engine?.fetchChanges()
    }

    /// DEBUG recovery hammer: re-enqueue every local entry as a save.
    /// Idempotent server-side (recordName = UUID) and conflict-safe (LWW).
    func forceReuploadAll() async {
        guard let ds = dataStore, let zoneID = targetZoneID() else { return }
        let ids = ds.entries.map { $0.id }
        seLog("forceReuploadAll: enqueueing \(ids.count) record save(s)")
        engine?.state.add(pendingRecordZoneChanges:
            ids.map { .saveRecord(EntryRecordCoding.makeRecordID(for: $0, zoneID: zoneID)) })
        try? await engine?.sendChanges()
    }

    /// CloudKit silent push arrived. The engine fetches on its own schedule, but
    /// nudging it here keeps foreground latency low. Returns true if consumed.
    @discardableResult
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return false }
        Task { await manualFetch() }
        return true
    }

    /// Leave share / revoke / sign-out. Local entries always stay.
    func stop(clearLedger: Bool) {
        seLog("stop(clearLedger: \(clearLedger))")
        cancellables.removeAll()
        engine = nil
        role = nil
        started = false
        if clearLedger {
            Task { await ledger.reset() }
            UserDefaults.standard.removeObject(forKey: kParticipantZoneKey)
            UserDefaults.standard.removeObject(forKey: kStateSharedKey)
            UserDefaults.standard.removeObject(forKey: kHeldSavesKey)
            UserDefaults.standard.removeObject(forKey: kHeldDeletesKey)
        }
    }

    /// Partner-badge lookup (facade delegates here; same table as always).
    func isPartnerEntry(_ id: UUID) -> Bool {
        let ids = UserDefaults.standard.stringArray(forKey: kPartnerEntryIDsKey) ?? []
        return ids.contains(id.uuidString)
    }

    // ─── Role ──────────────────────────────────────────────────────────────

    private func derivedRole() -> Role {
        (SyncStateManager.shared.isParticipant || SyncStateManager.shared.hasAcceptedShare)
            ? .participant : .owner
    }

    /// Self-healing: if reconcileState() flipped the role since the engine was
    /// built (accept share mid-session, leave, revoke), rebuild on the right DB.
    private func reconcileRoleIfNeeded() async {
        guard started, let current = role, current != derivedRole() else { return }
        seLog("reconcileRoleIfNeeded: role changed \(current.rawValue) → \(derivedRole().rawValue)")
        restart()
    }

    private func stateKey(for role: Role) -> String {
        role == .owner ? kStatePrivateKey : kStateSharedKey
    }

    // ─── Engine construction ───────────────────────────────────────────────

    private func buildEngine(for newRole: Role) {
        role = newRole
        let database = newRole == .owner
            ? container.privateCloudDatabase
            : container.sharedCloudDatabase

        var serialization: CKSyncEngine.State.Serialization?
        if let data = UserDefaults.standard.data(forKey: stateKey(for: newRole)) {
            serialization = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }

        let config = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: serialization,   // nil → engine does a full initial fetch
            delegate: delegateBox
        )
        engine = CKSyncEngine(config)
        seLog("buildEngine: role=\(newRole.rawValue) db=\(newRole == .owner ? "private" : "shared") state=\(serialization != nil ? "restored" : "fresh")")

        // Owner ensures the zone exists (idempotent; engine dedupes pending changes).
        // Participants must NEVER save/delete zones in the shared database.
        if newRole == .owner, !UserDefaults.standard.bool(forKey: kZoneSavedKey) {
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneName: kZoneName))])
        }
    }

    // The CKSyncEngineDelegate conformance lives on a small box object so this
    // class doesn't have to expose the delegate methods publicly.
    private lazy var delegateBox = SyncEngineDelegateBox(coordinator: self)

    // ─── Outbound: explicit change capture ─────────────────────────────────

    private func observeDataStore(_ ds: DataStore) {
        cancellables.removeAll()
        ds.$entries
            .dropFirst()
            // Coalesces bursts only — correctness does NOT depend on this delay.
            // The diff job reads entries FRESH at execution time, and the ledger
            // actor serializes everything, so no timing window exists.
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.scheduleDiff() }
            }
            .store(in: &cancellables)
    }

    private func scheduleDiff() async {
        guard let ds = dataStore else { return }
        let current = ds.entries                       // fresh read on MainActor
        let changes = await ledger.diff(against: current)
        guard !changes.isEmpty else { return }
        seLog("diff: \(changes.saves.count) save(s), \(changes.deletes.count) delete(s)")
        enqueue(changes)
        try? await engine?.sendChanges()
    }

    private func enqueue(_ changes: EntryChangeSet) {
        guard let zoneID = targetZoneID() else {
            // Participant whose shared zone isn't known yet (accept-propagation can
            // take ~45s). Hold the change PERSISTENTLY; flushed on zone discovery.
            holdChanges(changes)
            seLog("enqueue: zone unknown — held \(changes.saves.count)/\(changes.deletes.count) change(s)")
            return
        }
        engine?.state.add(pendingRecordZoneChanges:
            changes.saves.map   { .saveRecord(EntryRecordCoding.makeRecordID(for: $0, zoneID: zoneID)) } +
            changes.deletes.map { .deleteRecord(EntryRecordCoding.makeRecordID(for: $0, zoneID: zoneID)) })
    }

    private func targetZoneID() -> CKRecordZone.ID? {
        switch role {
        case .owner:
            return CKRecordZone.ID(zoneName: kZoneName, ownerName: CKCurrentUserDefaultName)
        case .participant:
            guard let raw = UserDefaults.standard.dictionary(forKey: kParticipantZoneKey),
                  let zoneName = raw["zoneName"] as? String,
                  let ownerName = raw["ownerName"] as? String else { return nil }
            return CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        case nil:
            return nil
        }
    }

    // Held-changes buffer (participant pre-zone-discovery), persisted as UUID strings.
    private func holdChanges(_ changes: EntryChangeSet) {
        var saves = Set(UserDefaults.standard.stringArray(forKey: kHeldSavesKey) ?? [])
        var deletes = Set(UserDefaults.standard.stringArray(forKey: kHeldDeletesKey) ?? [])
        changes.saves.forEach   { saves.insert($0.uuidString); deletes.remove($0.uuidString) }
        changes.deletes.forEach { deletes.insert($0.uuidString); saves.remove($0.uuidString) }
        UserDefaults.standard.set(Array(saves), forKey: kHeldSavesKey)
        UserDefaults.standard.set(Array(deletes), forKey: kHeldDeletesKey)
    }

    private func flushHeldChanges() {
        let saves = (UserDefaults.standard.stringArray(forKey: kHeldSavesKey) ?? []).compactMap(UUID.init)
        let deletes = (UserDefaults.standard.stringArray(forKey: kHeldDeletesKey) ?? []).compactMap(UUID.init)
        guard !saves.isEmpty || !deletes.isEmpty else { return }
        seLog("flushHeldChanges: \(saves.count) save(s), \(deletes.count) delete(s)")
        enqueue(EntryChangeSet(saves: saves, deletes: deletes))
        UserDefaults.standard.removeObject(forKey: kHeldSavesKey)
        UserDefaults.standard.removeObject(forKey: kHeldDeletesKey)
    }

    // ─── Migration from the legacy engine (one-shot) ───────────────────────

    private func migrateIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: kMigratedKey), let ds = dataStore else { return }
        seLog("migrateIfNeeded: migrating from legacy engine")

        // 1) Seed the ledger from current local entries — NO events emitted, so
        //    updating the app never mass re-uploads. modifiedAt = entry.timestamp
        //    is deterministic on both phones → seeding can't manufacture conflicts.
        await ledger.seed(from: ds.entries)

        // 2) Entries the old engine queued but never delivered genuinely need upload.
        let pendingIDs = (UserDefaults.standard.stringArray(forKey: "mommyslog.pendingUploadIDs") ?? [])
            .compactMap(UUID.init)
        if !pendingIDs.isEmpty {
            holdChanges(EntryChangeSet(saves: pendingIDs, deletes: []))
            seLog("migrateIfNeeded: carried \(pendingIDs.count) legacy pending upload(s)")
        }

        // 3) Delete the legacy manual push subscriptions — CKSyncEngine registers
        //    its own. Best-effort; a device still on the old app version may
        //    recreate them (harmless: duplicate pushes only, no data effect).
        let privateOp = CKModifySubscriptionsOperation(
            subscriptionsToSave: nil, subscriptionIDsToDelete: ["mommyslog-zone-changes"])
        privateOp.qualityOfService = .utility
        container.privateCloudDatabase.add(privateOp)
        let sharedOp = CKModifySubscriptionsOperation(
            subscriptionsToSave: nil, subscriptionIDsToDelete: ["mommyslog-shared-db-changes"])
        sharedOp.qualityOfService = .utility
        container.sharedCloudDatabase.add(sharedOp)

        // 4) Retire the legacy engine's keys. KEEP: partnerEntryIDs (badges),
        //    all SyncStateManager keys, hasAcceptedShare.
        let retired = ["mommyslog.serverChangeToken", "mommyslog.zoneCreated",
                       "mommyslog.uploadedEntryIDs", "mommyslog.entryFingerprints",
                       "mommyslog.pendingUploadIDs"]
        retired.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("mommyslog.sharedToken.") }
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }

        UserDefaults.standard.set(true, forKey: kMigratedKey)
        let seededCount = await ledger.count()
        seLog("migrateIfNeeded: done (ledger seeded with \(seededCount) entries)")
    }

    // ─── Delegate: event handling ──────────────────────────────────────────

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {

        case .stateUpdate(let e):
            // Persist first and always — losing it only costs a (safe) refetch.
            if let currentRole = role,
               let data = try? JSONEncoder().encode(e.stateSerialization) {
                UserDefaults.standard.set(data, forKey: stateKey(for: currentRole))
            }

        case .accountChange(let e):
            switch e.changeType {
            case .signIn:
                seLog("accountChange: signIn — restarting")
                restart()
            case .signOut, .switchAccounts:
                seLog("accountChange: signOut/switch — stopping (local data preserved)")
                stop(clearLedger: false)
                SyncStateManager.shared.markError("iCloud account changed — sync paused")
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let e):
            handleFetchedDatabaseChanges(e)

        case .fetchedRecordZoneChanges(let e):
            await handleFetchedRecordZoneChanges(e)

        case .sentRecordZoneChanges(let e):
            await handleSentRecordZoneChanges(e, syncEngine: syncEngine)

        case .sentDatabaseChanges(let e):
            if e.savedZones.contains(where: { $0.zoneID.zoneName == kZoneName }) {
                UserDefaults.standard.set(true, forKey: kZoneSavedKey)
                seLog("sentDatabaseChanges: zone saved")
            }

        case .willFetchChanges, .willSendChanges:
            SyncStateManager.shared.markSyncing()

        case .didFetchChanges, .didSendChanges:
            if syncEngine.state.pendingRecordZoneChanges.isEmpty {
                SyncStateManager.shared.markSynced()
            }

        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            seLog("handleEvent: unknown event \(event)")
        }
    }

    private func handleFetchedDatabaseChanges(_ e: CKSyncEngine.Event.FetchedDatabaseChanges) {
        // Participant zone discovery: the shared MommysLogZone appearing in the
        // shared DB replaces the old 45s polling + empty-zone heuristics.
        for zone in e.modifications where zone.zoneID.zoneName == kZoneName {
            if role == .participant {
                UserDefaults.standard.set(
                    ["zoneName": zone.zoneID.zoneName, "ownerName": zone.zoneID.ownerName],
                    forKey: kParticipantZoneKey)
                seLog("fetchedDatabaseChanges: shared zone discovered (owner=\(zone.zoneID.ownerName))")
                flushHeldChanges()
            }
        }

        for deletion in e.deletions where deletion.zoneID.zoneName == kZoneName {
            switch role {
            case .owner:
                // Our zone vanished (e.g. user reset iCloud data) — recreate + re-upload.
                seLog("fetchedDatabaseChanges: OWN zone deleted — recreating and re-uploading")
                UserDefaults.standard.removeObject(forKey: kZoneSavedKey)
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneName: kZoneName))])
                Task { await forceReuploadAll() }
            case .participant:
                // THE reliable revocation signal (replaces the 3-strike guess):
                // the owner deleted the share/zone. Clear participant state; keep
                // all local entries.
                seLog("fetchedDatabaseChanges: shared zone deleted — owner revoked access")
                SyncStateManager.shared.isParticipant = false
                SyncStateManager.shared.isPartnerConnected = false
                SyncStateManager.shared.hasPartnerShare = false
                SyncStateManager.shared.hasAcceptedShare = false
                SyncStateManager.shared.deactivatePro()
                SyncStateManager.shared.markError("Partner disconnected — open Partner Sync to check")
                stop(clearLedger: true)
            case nil:
                break
            }
        }
    }

    private func handleFetchedRecordZoneChanges(_ e: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        guard let ds = dataStore else { return }

        // All fetched records go to the LEDGER (fresh systemFields/modifiedAt), but
        // only records whose content actually differs — or that are missing locally —
        // touch the DataStore. A full refetch of ~1500 identical records would
        // otherwise re-sort + re-encode + re-save the whole store per batch on the
        // main thread (visible UI jank, e.g. slow keyboard while a refetch runs).
        var ledgerUpserts: [(entry: EntryWrapper, record: CKRecord)] = []
        var applyToStore: [EntryWrapper] = []
        var partnerIDs: [UUID] = []
        let localIDs = Set(ds.entries.map { $0.id })

        for modification in e.modifications {
            let record = modification.record
            guard record.recordType == EntryRecordCoding.recordType,
                  let entry = EntryRecordCoding.makeEntry(from: record) else { continue }

            let serverFP = EntryRecordCoding.fingerprint(entry)
            let localFP = await ledger.fingerprint(for: entry.id)

            // Last-writer-wins guard: if we hold a NEWER local edit of this entry
            // that hasn't been sent yet, skip the older server copy — our pending
            // save will overwrite it (and the conflict handler agrees, same clock).
            if let localFP, localFP != serverFP,
               let localModified = await ledger.modifiedAt(for: entry.id),
               localModified > EntryRecordCoding.modifiedAt(of: record) {
                seLog("fetched: skipping older server copy of \(entry.id) (local edit is newer)")
                continue
            }

            ledgerUpserts.append((entry, record))
            // No-op skip: identical content AND present locally → ledger-only.
            if localFP != serverFP || !localIDs.contains(entry.id) {
                applyToStore.append(entry)
            }
            // Badge entries created by the OTHER person. CloudKit reports the
            // current user's own records as CKCurrentUserDefaultName.
            if let creator = record.creatorUserRecordID?.recordName,
               creator != CKCurrentUserDefaultName {
                partnerIDs.append(entry.id)
            }
        }

        let deletions = e.deletions.compactMap { UUID(uuidString: $0.recordID.recordName) }

        guard !ledgerUpserts.isEmpty || !deletions.isEmpty else { return }
        seLog("fetched: \(ledgerUpserts.count) record(s) (\(applyToStore.count) changed), \(deletions.count) deletion(s)")

        // INVARIANT: ledger BEFORE DataStore — the next diff must see no phantom
        // local change for these ids (this ordering is what kills the echo loop).
        await ledger.recordInbound(upserts: ledgerUpserts, deletes: deletions)
        markPartnerEntries(partnerIDs)
        ds.applyInboundUpserts(applyToStore)
        ds.applyInboundDeletes(Set(deletions))
        SyncStateManager.shared.markSynced()
    }

    private func handleSentRecordZoneChanges(_ e: CKSyncEngine.Event.SentRecordZoneChanges,
                                             syncEngine: CKSyncEngine) async {
        for record in e.savedRecords {
            await ledger.recordSaved(record)
        }
        if !e.savedRecords.isEmpty {
            seLog("sent: \(e.savedRecords.count) record(s) saved")
        }

        for failure in e.failedRecordSaves {
            let recordID = failure.record.recordID
            guard let id = UUID(uuidString: recordID.recordName) else { continue }

            switch failure.error.code {
            case .serverRecordChanged:
                // CONFLICT — last-writer-wins on modifiedAt.
                guard let serverRecord = failure.error.serverRecord else {
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                    continue
                }
                let serverModified = EntryRecordCoding.modifiedAt(of: serverRecord)
                let localModified = await ledger.modifiedAt(for: id) ?? .distantPast
                if localModified > serverModified {
                    // Local wins: adopt the server record's change tag, retry the save.
                    seLog("conflict on \(id): LOCAL wins (\(localModified) > \(serverModified))")
                    await ledger.recordSaved(serverRecord)   // cache fresh system fields
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                } else {
                    // Server wins: drop our pending save, apply the server copy inbound.
                    seLog("conflict on \(id): SERVER wins (\(serverModified) >= \(localModified))")
                    syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                    if let entry = EntryRecordCoding.makeEntry(from: serverRecord), let ds = dataStore {
                        await ledger.recordInbound(upserts: [(entry, serverRecord)], deletes: [])
                        ds.applyInboundUpserts([entry])
                    }
                }

            case .zoneNotFound:
                seLog("sent: zoneNotFound for \(id) — re-saving zone + retrying")
                if role == .owner {
                    UserDefaults.standard.removeObject(forKey: kZoneSavedKey)
                    engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneName: kZoneName))])
                }
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

            case .unknownItem:
                // Record vanished server-side — drop stale change tag, recreate fresh.
                seLog("sent: unknownItem for \(id) — recreating")
                await ledger.clearSystemFields(for: id)
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

            case .networkFailure, .networkUnavailable, .serviceUnavailable,
                 .zoneBusy, .requestRateLimited, .notAuthenticated:
                // Transient — re-enqueue; the engine retries with its own backoff.
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

            default:
                seLog("sent: save of \(id) failed — \(failure.error.localizedDescription)")
                SyncStateManager.shared.markError("Some entries will retry shortly")
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        }

        for (recordID, error) in e.failedRecordDeletes {
            switch error.code {
            case .unknownItem:
                break   // already gone — success by another name
            default:
                syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            }
        }
    }

    // ─── Delegate: building the outbound batch ─────────────────────────────

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            guard let self,
                  let uuid = UUID(uuidString: recordID.recordName),
                  let entry = await self.currentEntry(for: uuid) else {
                // Entry was deleted while the save was pending — drop the save;
                // the ledger diff has already enqueued the matching delete.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }

            // Base the save on cached system fields (server change tag) when we
            // have them, so .ifServerRecordUnchanged passes without a conflict.
            let record: CKRecord
            if let sys = await self.ledger.systemFields(for: uuid),
               let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: sys),
               let base = CKRecord(coder: unarchiver) {
                record = base
            } else {
                record = CKRecord(recordType: EntryRecordCoding.recordType, recordID: recordID)
            }

            let modifiedAt = await self.ledger.modifiedAt(for: uuid) ?? entry.timestamp
            guard EntryRecordCoding.applyEntryFields(entry, modifiedAt: modifiedAt, to: record) else {
                return nil
            }
            return record
        }
    }

    // ─── Helpers ───────────────────────────────────────────────────────────

    private func currentEntry(for id: UUID) -> EntryWrapper? {
        dataStore?.entries.first { $0.id == id }
    }

    private func markPartnerEntries(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var stored = Set(UserDefaults.standard.stringArray(forKey: kPartnerEntryIDsKey) ?? [])
        ids.forEach { stored.insert($0.uuidString) }
        UserDefaults.standard.set(Array(stored), forKey: kPartnerEntryIDsKey)
    }
}

// ─── Delegate box ─────────────────────────────────────────────────────────────
// CKSyncEngineDelegate conformance on a separate object keeps SyncCoordinator's
// public surface clean and avoids exposing the delegate methods to callers.
// @unchecked Sendable is safe: the only stored property is an unowned reference
// to the singleton @MainActor coordinator, and both methods immediately hop to it.
private final class SyncEngineDelegateBox: CKSyncEngineDelegate, @unchecked Sendable {
    unowned let coordinator: SyncCoordinator

    init(coordinator: SyncCoordinator) {
        self.coordinator = coordinator
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await coordinator.handleEvent(event, syncEngine: syncEngine)
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await coordinator.nextRecordZoneChangeBatch(context, syncEngine: syncEngine)
    }
}
