//
//  CloudKitManager.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// This is the "translator" between your app's local data and Apple's iCloud.
//
// Think of iCloud like a shared whiteboard in the cloud.
// Mom's phone draws on the whiteboard. Partner's phone reads the whiteboard.
// This file handles all the marker-and-eraser work.
//
// Outbound: When mom logs a feeding → this file uploads it to iCloud.
// Inbound:  When partner or another device adds an entry → this file
//           downloads it and gives it to DataStore.
//
// The "zone" is like a private folder inside iCloud — only people
// who were invited can see what's in it.
// ─────────────────────────────────────────────────────────────

import CloudKit
import Combine
import CryptoKit
import Foundation

// ⚠️ IMPORTANT: Replace this string with your actual CloudKit container ID.
// You find it in Xcode → Target → Signing & Capabilities → iCloud → Containers.
// It looks like: iCloud.com.yourname.MomBabyLogger
// internal (no private) so SharingManager can share these constants.
let kContainerID = "iCloud.lilycantilloapp.mommysblog"

// The name of our private "folder" inside iCloud.
// This never changes — it's how CloudKit knows where our records live.
let kZoneName = "MommysLogZone"

// The CloudKit record type. Must match what you created in the dashboard.
private let kRecordType = "Entry"

// UserDefaults keys — used to remember state between app launches.
private let kServerChangeTokenKey = "mommyslog.serverChangeToken"
private let kZoneCreatedKey       = "mommyslog.zoneCreated"
private let kPendingUploadIDsKey  = "mommyslog.pendingUploadIDs"

// All `[CloudKit]` diagnostic logging goes through this. It compiles OUT of App Store
// (Release) builds, so production stays quiet, while debug builds keep full sync tracing.
// To temporarily see these in a Release build, change `#if DEBUG` to `if true`.
private func ckLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

// 📖 SWIFT CONCEPT: @MainActor
// CloudKit callbacks come back on background threads.
// Marking this class @MainActor means "whenever a property changes or
// a function runs, always do it on the main thread."
// SwiftUI needs the main thread for UI updates, so this keeps us safe.
@MainActor
class CloudKitManager: ObservableObject {

    // 📖 SWIFT CONCEPT: Singleton
    // One instance for the whole app. Any file can call CloudKitManager.shared.
    static let shared = CloudKitManager()

    // ─── CloudKit References ───────────────────────────────────────────────

    // 📖 SWIFT CONCEPT: CKContainer → CKDatabase → CKRecordZone
    // Container = your app's entire iCloud space
    // Database  = "private" (only you) or "shared" (you + invited people)
    // Zone      = a named sub-folder inside the database
    //
    // We use privateDatabase for mom's own entries and
    // sharedDatabase for reading entries a partner shared with us.

    private lazy var container: CKContainer = {
        CKContainer(identifier: kContainerID)
    }()

    private lazy var privateDB: CKDatabase = {
        container.privateCloudDatabase
    }()

    private lazy var sharedDB: CKDatabase = {
        container.sharedCloudDatabase
    }()

    // The zone is like a folder. We create it once and reuse it.
    private lazy var zone: CKRecordZone = {
        CKRecordZone(zoneName: kZoneName)
    }()

    // ─── State ─────────────────────────────────────────────────────────────

    // A weak reference so we can call dataStore.applyInboundEntries() later.
    // 📖 SWIFT CONCEPT: weak var
    // "weak" means: if DataStore goes away, this becomes nil automatically.
    // This prevents a retain cycle (both objects keeping each other alive forever).
    private weak var dataStore: DataStore?

    // 📖 SWIFT CONCEPT: AnyCancellable
    // Combine subscriptions need to be "held" somewhere or they cancel immediately.
    // Storing them in this Set keeps them alive as long as CloudKitManager is alive.
    private var cancellables = Set<AnyCancellable>()

    // Holds the periodic refresh timer so it stays alive while sync is active.
    // Fires every 60 seconds to catch entries logged on the partner device while
    // both phones are in the foreground (scenePhase doesn't change in that case).
    private var refreshTimer: AnyCancellable?

    // Tracks how many consecutive times fetchSharedChanges() has seen empty zones
    // while hasAcceptedShare is true. A single empty response could be a transient
    // CloudKit propagation delay. Three in a row almost certainly means the owner
    // revoked the share — surface an actionable error after the threshold.
    private var consecutiveEmptyZones = 0

    // Guards the Combine observer from reacting to deletions we make locally
    // when applying an inbound edit (delete old version, re-add updated version).
    // Without this, deleting the old version would trigger syncDeletedEntries
    // which would remove the record from CloudKit right before we re-add it.
    private var isApplyingInboundEdits = false

    // Guards against concurrent fetches. Multiple triggers (silent push, 60s timer, foreground,
    // PartnerSyncView open) can call fetchChanges() at once; two overlapping inbound applies both
    // compute "existing IDs" before either appends, then both add the same record → duplicate
    // entries. Serializing fetches prevents that.
    private var isFetching = false

    // Guards against concurrent OUTBOUND syncs. The observer, boot, foreground push, and
    // PartnerSyncView open can all run syncNewEntries/syncEditedEntries at once. Each does a
    // read-modify-write on the fingerprints/uploadedIDs in UserDefaults, so concurrent runs
    // clobber each other's saves — fingerprints never persist, so every cycle re-flags ALL
    // entries as "edited" and re-uploads the whole history forever. Serializing fixes it.
    private var isSyncingOutbound = false

    // UUIDs of entries we tried to upload but failed (e.g. no internet).
    // Persisted in UserDefaults so we retry on next launch.
    private var pendingRetryIDs: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: kPendingUploadIDsKey) ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: kPendingUploadIDsKey)
        }
    }

    // The "bookmark" CloudKit uses to know which changes we've already seen.
    // 📖 SWIFT CONCEPT: Data? (Optional)
    // The ? means this can be nil (first launch — no token yet).
    // Each time we fetch changes, CloudKit gives us a new token.
    // We save it and send it next time so we only get NEW changes.
    private var serverChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: kServerChangeTokenKey) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
        set {
            if let token = newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: kServerChangeTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: kServerChangeTokenKey)
            }
        }
    }

    private init() {}

    // ─── Setup ─────────────────────────────────────────────────────────────

    // Call this once from MomBabyLoggerApp.swift when the app starts.
    // It wires everything together so sync "just works" from then on.
    func configure(with dataStore: DataStore) {
        self.dataStore = dataStore
        Task {
            if !SyncStateManager.shared.isPro {
                // Case 1: hasAcceptedShare is the durable ground truth for participants.
                // Restore state immediately without a CloudKit round-trip.
                // This handles the case where fetchSharedChanges() previously wiped
                // isParticipant + isPro due to an empty allRecordZones() response.
                if SyncStateManager.shared.hasAcceptedShare || SyncStateManager.shared.isParticipant {
                    SyncStateManager.shared.isParticipant = true
                    SyncStateManager.shared.activatePro()
                }
                // Case 2: reinstall — AppStorage is gone but shared zone still exists in iCloud.
                else if let sharedZones = try? await sharedDB.allRecordZones(), !sharedZones.isEmpty {
                    SyncStateManager.shared.isParticipant = true
                    SyncStateManager.shared.activatePro()
                }
            }
            guard SyncStateManager.shared.isPro else { return }
            await boot()
        }
    }

    // Called when user purchases Pro for the first time.
    // Runs the same boot sequence but from the Pro activation path.
    func activateSync(with dataStore: DataStore) {
        self.dataStore = dataStore
        Task {
            await boot()
        }
    }

    // Called after Phone 2 accepts a share while the app is already running.
    // Always clears shared zone tokens first so the subsequent fetchSharedChanges()
    // does a full re-download instead of a delta that might start after Phone 1's
    // entries were uploaded (producing "Up to date" with an empty data store).
    func startSyncAfterJoining() {
        guard dataStore != nil else { return }
        clearSharedZoneTokens()
        Task { await boot() }
    }

    // Clears the uploaded-entry tracking set and re-sends every local entry to
    // CloudKit. Use when Phone 2 can't see Phone 1's historical entries — it means
    // they were never successfully uploaded to the shared zone.
    func forceReuploadAll() {
        guard !SyncStateManager.shared.isParticipant else { return }
        UserDefaults.standard.removeObject(forKey: kUploadedIDsKey)
        Task { await boot() }
    }

    // Internal boot: create the iCloud zone, subscribe to push notifications,
    // wire the Combine observer, then do an initial fetch.
    private func boot() async {
        SyncStateManager.shared.markSyncing()
        do {
            // Owner path: create the private zone + subscribe to it.
            // Participant path: zone lives in sharedDB — subscribe there instead.
            if SyncStateManager.shared.isParticipant {
                try await setupSharedSubscriptionIfNeeded()
                if let ds = dataStore {
                    await performOutboundSync(ds.entries)
                }
            } else {
                try await setupZoneIfNeeded()
                try await setupSubscriptionIfNeeded()
                if let ds = dataStore {
                    await performOutboundSync(ds.entries)
                }
            }
            observeDataStore()
            await fetchChanges()
            await retryPending()
            startPeriodicRefresh()
        } catch {
            SyncStateManager.shared.markError("Setup failed: \(error.localizedDescription)")
        }
    }

    // ─── Zone Setup ────────────────────────────────────────────────────────

    // 📖 SWIFT CONCEPT: async/await + throws
    // `async` means "this function can pause and resume without blocking the UI."
    // `throws` means "this function can fail and bubble up an error."
    // `try await` means "run this async operation and if it fails, throw the error up."
    //
    // Analogy: ordering food at a restaurant (async = you don't stand at the counter;
    // you sit and wait to be called) + getting the wrong order back (throws = error).
    private func setupZoneIfNeeded() async throws {
        // Skip if we already created the zone on a previous launch.
        if UserDefaults.standard.bool(forKey: kZoneCreatedKey) { return }

        let operation = CKModifyRecordZonesOperation(
            recordZonesToSave: [zone],
            recordZoneIDsToDelete: nil
        )

        // 📖 SWIFT CONCEPT: Continuation
        // CloudKit's older API uses callbacks (completion handlers).
        // `withCheckedThrowingContinuation` wraps a callback in async/await
        // so we can use the modern `try await` style.
        // It "pauses" here, waits for the callback, then "resumes."
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    UserDefaults.standard.set(true, forKey: kZoneCreatedKey)
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            privateDB.add(operation)
        }
    }

    // ─── Push Subscription ─────────────────────────────────────────────────

    // This tells CloudKit: "When anything changes in our zone, send a silent
    // push notification to all my devices."  That's how the partner's phone
    // knows to fetch new entries — Apple taps it on the shoulder.
    private func setupSubscriptionIfNeeded() async throws {
        let subscriptionID = "mommyslog-zone-changes"

        // Check if we already registered this subscription.
        let existingIDs = try? await privateDB.allSubscriptions().map { $0.subscriptionID }
        if existingIDs?.contains(subscriptionID) == true { return }

        // 📖 SWIFT CONCEPT: CKRecordZoneSubscription
        // This is a "standing order" we place with CloudKit once.
        // It lives on Apple's server. Even if the app is closed, Apple will
        // send a push notification when data changes.
        let subscription = CKRecordZoneSubscription(
            zoneID: zone.zoneID,
            subscriptionID: subscriptionID
        )

        // notificationInfo tells CloudKit what kind of push to send.
        // shouldSendContentAvailable = true → silent push (no sound/banner).
        // The app wakes up in the background and calls fetchChanges().
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        try await privateDB.save(subscription)
    }

    // Partner/nanny device subscribes to the shared database so Apple sends a
    // silent push whenever mom (the owner) adds or changes an entry.
    // CKDatabaseSubscription covers ALL zones in the shared database — no zone
    // ID needed, which is important because we don't know the owner's zone ID upfront.
    private func setupSharedSubscriptionIfNeeded() async throws {
        let subscriptionID = "mommyslog-shared-db-changes"
        let existingIDs = try? await sharedDB.allSubscriptions().map { $0.subscriptionID }
        if existingIDs?.contains(subscriptionID) == true { return }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        try await sharedDB.save(subscription)
    }

    // ─── Combine Observer ──────────────────────────────────────────────────

    // 📖 SWIFT CONCEPT: Combine Publisher
    // DataStore.$entries is a "live stream" — every time entries changes,
    // it emits the new value.  `.sink` is like putting a bucket under a tap.
    // `.debounce` means: "wait 1.5 seconds of quiet before reacting."
    // This prevents uploading 10 times if mom taps save quickly.
    private func observeDataStore() {
        guard let dataStore else { return }

        dataStore.$entries
            .dropFirst()               // skip the initial value at subscription time
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] newEntries in
                guard let self else { return }
                // isApplyingInboundSync = true means we just got data FROM iCloud.
                // We must NOT upload it back — that would create an infinite loop.
                // isApplyingInboundEdits = true means we're mid delete+re-add for an
                // inbound edit — don't react to the temporary deletion either.
                guard !dataStore.isApplyingInboundSync, !self.isApplyingInboundEdits else {
                    return
                }
                Task { await self.performOutboundSync(newEntries) }
            }
            .store(in: &cancellables)  // keep the subscription alive
    }

    // ─── Outbound Sync (App → iCloud) ──────────────────────────────────────

    // Figures out which entries haven't been uploaded yet and sends them.
    // Also retries anything that failed before.
    private func syncNewEntries(_ currentEntries: [EntryWrapper]) async {
        let uploadedIDs = loadUploadedIDs()
        let toUpload = currentEntries.filter { !uploadedIDs.contains($0.id.uuidString) }
        ckLog("[CloudKit] syncNewEntries: total=\(currentEntries.count) alreadyUploaded=\(uploadedIDs.count) toUpload=\(toUpload.count)")
        guard !toUpload.isEmpty else { return }

        SyncStateManager.shared.markSyncing()
        await upload(entries: toUpload)
    }

    // Detects entries deleted locally that still exist in CloudKit and removes them.
    // Without this, deleted entries come back as "zombies" after reconnect or forceRefetchAll.
    // Also propagates the deletion to the other phone via recordWithIDWasDeletedBlock.
    // Safe for both owner (privateDB) and participant (sharedDB) — resolveUploadTarget() routes correctly.
    private func syncDeletedEntries(_ currentEntries: [EntryWrapper]) async {
        // HARD GUARD against spurious deletions. While we're applying inbound edits (which
        // delete-then-readd locally) or doing a full re-fetch, an entry can be momentarily
        // absent from currentEntries without the user having deleted anything. Acting on that
        // transient gap would wrongly delete the record from CloudKit and propagate the deletion
        // to the partner. Only treat an entry as user-deleted when no inbound/fetch is in flight.
        if isApplyingInboundEdits || isFetching || (dataStore?.isApplyingInboundSync ?? false) {
            return
        }

        let uploaded = loadUploadedIDs()
        let currentIDs = Set(currentEntries.map { $0.id.uuidString })
        let deletedIDs = uploaded.subtracting(currentIDs)

        guard !deletedIDs.isEmpty else { return }
        ckLog("[CloudKit] syncDeletedEntries: \(deletedIDs.count) locally-deleted entry(ies) — removing from CloudKit")

        guard let (targetDB, targetZoneID) = await resolveUploadTarget() else {
            ckLog("[CloudKit] syncDeletedEntries: zone unavailable — will retry on next cycle")
            return
        }

        let recordIDs = deletedIDs.map { CKRecord.ID(recordName: $0, zoneID: targetZoneID) }
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)

        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success: cont.resume()
                    case .failure(let err): cont.resume(throwing: err)
                    }
                }
                targetDB.add(operation)
            }
            var remaining = loadUploadedIDs()
            deletedIDs.forEach { remaining.remove($0) }
            saveUploadedIDs(remaining)
            // Remove fingerprints for deleted entries so stale data doesn't accumulate.
            var fps = loadFingerprints()
            deletedIDs.forEach { fps.removeValue(forKey: $0) }
            saveFingerprints(fps)
            ckLog("[CloudKit] syncDeletedEntries: removed \(deletedIDs.count) record(s) from CloudKit")
        } catch {
            ckLog("[CloudKit] syncDeletedEntries: FAILED — \(error.localizedDescription)")
        }
    }

    // Detects entries that were already uploaded but whose content changed locally
    // (e.g. user edited the time, notes, or ounces) and re-uploads them.
    // Uses a fingerprint dictionary (short hash of JSON) to detect changes.
    // Entries with no stored fingerprint were uploaded before fingerprinting was added —
    // treat them as potentially edited and re-upload. uploadEdited() saves their fingerprint
    // on success, so this only fires once per entry.
    private func syncEditedEntries(_ currentEntries: [EntryWrapper]) async {
        let uploaded = loadUploadedIDs()
        var fingerprints = loadFingerprints()
        var edited: [EntryWrapper] = []
        var baselineChanged = false

        for entry in currentEntries {
            let id = entry.id.uuidString
            guard uploaded.contains(id) else { continue }
            let current = entryFingerprint(entry)   // normalized "F|…" / "D|…" string

            guard let stored = fingerprints[id] else {
                // Never tracked — adopt the current content as the baseline WITHOUT
                // re-uploading. CloudKit already holds this entry; future real edits
                // will be detected by comparing fingerprints.
                fingerprints[id] = current
                baselineChanged = true
                continue
            }

            if stored == current { continue }   // unchanged

            // Distinguish a REAL EDIT from a one-time fingerprint-FORMAT migration. The current
            // format is the normalized "F|…|…" / "D|…|…" string (always contains "|"). Older
            // stored fingerprints were SHA-256 hex / base64 prefixes (no "|"). Only treat it as
            // a format migration when the STORED value isn't the new format. (The old code used
            // a LENGTH check — but normalized fingerprints vary in length with the oz value and
            // note, so a genuine edit that changed the length was wrongly skipped as a migration.
            // That was the bug that stopped owner edits from ever uploading.)
            if !stored.contains("|") {
                fingerprints[id] = current
                baselineChanged = true
                continue
            }

            // Both are normalized fingerprints and genuinely differ → a real edit.
            edited.append(entry)
        }

        if baselineChanged { saveFingerprints(fingerprints) }
        guard !edited.isEmpty else {
            return
        }
        ckLog("[CloudKit] syncEditedEntries: \(edited.count) edited entry(ies) — re-uploading to CloudKit")
        await uploadEdited(entries: edited)
    }

    // Does the actual CKRecord save. Marks entries as uploaded or queues for retry.
    // Participants write to sharedDB (mom's zone); owner writes to privateDB.
    // CloudKit recommends batches of ≤400 records per operation.
    // Sending 1000+ records in one shot can trigger limitExceeded errors.
    private let kUploadBatchSize = 400

    // Removes entries that share a UUID (keeps the first of each). CloudKit rejects ANY
    // operation containing two records with the same recordID ("you can't save the same
    // record twice"), which permanently failed every batch that held a duplicate and stalled
    // all syncing. Duplicates were created by earlier concurrent-fetch churn.
    private func deduplicatedByID(_ entries: [EntryWrapper]) -> [EntryWrapper] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.id.uuidString).inserted }
    }

    private func upload(entries toUpload: [EntryWrapper]) async {
        // If the shared zone isn't available yet, queue everything for retry.
        // This prevents writing to the wrong database while CloudKit propagates.
        guard let (targetDB, targetZoneID) = await resolveUploadTarget() else {
            ckLog("[CloudKit] upload: shared zone unavailable — queuing \(toUpload.count) entry(ies) for retry")
            for entry in toUpload { pendingRetryIDs.insert(entry.id.uuidString) }
            SyncStateManager.shared.markError("Sync pending — will retry shortly")
            return
        }
        let dbLabel = SyncStateManager.shared.isParticipant ? "sharedDB" : "privateDB"

        // Batch the ENTRIES (not records) so progress can be persisted after EACH batch.
        // The old code saved uploadedIDs only after ALL batches finished, so a single batch
        // failure (or the app closing mid-upload) discarded all progress — uploadedIDs fell
        // back to 0 and the whole history re-uploaded next time, never converging.
        // Drop duplicate UUIDs — CloudKit rejects an operation with two records of the same ID.
        let uniqueEntries = deduplicatedByID(toUpload)
        let entryBatches = stride(from: 0, to: uniqueEntries.count, by: kUploadBatchSize).map {
            Array(uniqueEntries[$0..<min($0 + kUploadBatchSize, uniqueEntries.count)])
        }
        ckLog("[CloudKit] upload: \(uniqueEntries.count) unique entry(ies) → \(entryBatches.count) batch(es) to \(dbLabel) zone=\(targetZoneID.zoneName)")

        var anyFailed = false
        for (i, entryBatch) in entryBatches.enumerated() {
            let records = entryBatch.compactMap { makeRecord(from: $0, zoneID: targetZoneID) }
            guard !records.isEmpty else { continue }

            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            // .allKeys (overwrite) not .ifServerRecordUnchanged: the local entry is the source
            // of truth for the owner's own logs. .ifServerRecordUnchanged rejects any entry whose
            // server copy exists but whose local change-tag was lost (from earlier churn), and
            // because the zone commits atomically that ONE rejection fails the whole batch — so a
            // brand-new log bundled with stale ones never uploads.
            operation.savePolicy = .allKeys

            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    operation.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success: continuation.resume()
                        case .failure(let error): continuation.resume(throwing: error)
                        }
                    }
                    targetDB.add(operation)
                }
                // Persist progress for THIS batch immediately — it can never reset to 0.
                var uploaded = loadUploadedIDs()
                var fps = loadFingerprints()
                for entry in entryBatch {
                    uploaded.insert(entry.id.uuidString)
                    pendingRetryIDs.remove(entry.id.uuidString)
                    fps[entry.id.uuidString] = entryFingerprint(entry)
                }
                saveUploadedIDs(uploaded)
                saveFingerprints(fps)
                ckLog("[CloudKit] upload: batch \(i+1)/\(entryBatches.count) SUCCESS (\(entryBatch.count)) — uploadedIDs now \(uploaded.count)")
            } catch {
                ckLog("[CloudKit] upload: batch \(i+1)/\(entryBatches.count) FAILED — \(error.localizedDescription)")
                for entry in entryBatch { pendingRetryIDs.insert(entry.id.uuidString) }
                anyFailed = true
                // Keep going — other batches (incl. a brand-new log) can still succeed and persist.
            }
        }

        if anyFailed {
            SyncStateManager.shared.markError("Some entries will retry shortly")
        } else {
            ckLog("[CloudKit] upload: ALL entries saved to \(dbLabel)")
            SyncStateManager.shared.markSynced()
        }
    }

    // Uploads EDITS to existing entries. The previous version overwrote a fresh, tag-less
    // CKRecord with savePolicy = .allKeys — which the PARTICIPANT's zone-change delta did NOT
    // report (owner edits never reached the partner). This version does a proper
    // fetch-modify-save: fetch the existing server record (carrying its recordChangeTag),
    // write the new fields, and save with the change-tag-aware policy. That registers a real
    // modification in the zone change feed, which the participant's delta reports normally.
    //
    // Edits are rare and arrive one at a time (the normalized fingerprint prevents the old
    // "everything edited" storm), so per-record fetch-modify-save is cheap here.
    private func uploadEdited(entries toUpload: [EntryWrapper]) async {
        guard let (targetDB, targetZoneID) = await resolveUploadTarget() else {
            ckLog("[CloudKit] uploadEdited: zone unavailable — skipping \(toUpload.count) edited entry(ies)")
            return
        }
        let uniqueEntries = deduplicatedByID(toUpload)
        guard !uniqueEntries.isEmpty else { return }

        let dbLabel = SyncStateManager.shared.isParticipant ? "sharedDB" : "privateDB"
        var succeeded = 0
        for entry in uniqueEntries {
            let short = entry.id.uuidString.prefix(8)
            let recordID = CKRecord.ID(recordName: entry.id.uuidString, zoneID: targetZoneID)
            do {
                // Fetch the existing record so we carry its recordChangeTag. If it isn't on the
                // server yet, fall back to a fresh record (treated as a create).
                let serverRecord: CKRecord
                do {
                    serverRecord = try await targetDB.record(for: recordID)
                } catch let ckError as CKError where ckError.code == .unknownItem {
                    serverRecord = CKRecord(recordType: kRecordType, recordID: recordID)
                }
                applyEntryFields(entry, to: serverRecord)

                do {
                    try await saveRecord(serverRecord, to: targetDB, policy: .ifServerRecordUnchanged)
                } catch let ckError as CKError where ckError.code == .serverRecordChanged {
                    // Someone changed it server-side between our fetch and save. Re-fetch the
                    // latest, re-apply our fields, and save with changedKeys to win the conflict.
                    let latest = try await targetDB.record(for: recordID)
                    applyEntryFields(entry, to: latest)
                    try await saveRecord(latest, to: targetDB, policy: .changedKeys)
                }

                // Persist the fingerprint immediately so this entry isn't re-flagged next cycle.
                var fps = loadFingerprints()
                fps[entry.id.uuidString] = entryFingerprint(entry)
                saveFingerprints(fps)
                succeeded += 1
            } catch {
            }
        }
        ckLog("[CloudKit] uploadEdited: \(succeeded)/\(uniqueEntries.count) edited record(s) saved")
        if succeeded > 0 { SyncStateManager.shared.markSynced() }
    }

    // Saves a single CKRecord with the given save policy, bridging the callback API to async.
    private func saveRecord(_ record: CKRecord, to db: CKDatabase, policy: CKModifyRecordsOperation.RecordSavePolicy) async throws {
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = policy
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let err): cont.resume(throwing: err)
                }
            }
            db.add(operation)
        }
    }

    // Returns the right (database, zoneID) pair for uploads, or nil if unavailable.
    // Participant → sharedDB using the discovered shared zone (retries 3×).
    // Owner       → privateDB using our own zone.
    //
    // WHY nil instead of a privateDB fallback for participants:
    // The old code fell back to the participant's own privateDB when the shared zone
    // wasn't found yet (transient CloudKit delay). That silently wrote the entry to
    // the wrong database — Phone 1 (owner) could never see it. Returning nil instead
    // queues the entry for retry so it uploads to the correct zone once available.
    private func resolveUploadTarget() async -> (CKDatabase, CKRecordZone.ID)? {
        guard SyncStateManager.shared.isParticipant else {
            return (privateDB, zone.zoneID)
        }
        // Retry up to 3 times with increasing delays (2s, 4s) to ride out
        // transient CloudKit zone-propagation delays without writing to wrong DB.
        for attempt in 1...3 {
            if let sharedZone = try? await sharedDB.allRecordZones()
                .first(where: { $0.zoneID.zoneName == kZoneName }) {
                return (sharedDB, sharedZone.zoneID)
            }
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
            }
        }
        ckLog("[CloudKit] resolveUploadTarget: shared zone not found after 3 attempts — will retry later")
        return nil
    }

    // Retries any entries that failed to upload on a previous session.
    private func retryPending() async {
        guard !pendingRetryIDs.isEmpty, let dataStore else { return }
        let retryIDs = pendingRetryIDs
        let entriesToRetry = dataStore.entries.filter { retryIDs.contains($0.id.uuidString) }
        guard !entriesToRetry.isEmpty else {
            // IDs queued but entries no longer exist — clean up.
            pendingRetryIDs = []
            return
        }
        await upload(entries: entriesToRetry)
    }

    // Pushes locally-pending changes (new / deleted / edited) UP to CloudKit.
    // Lightweight — no zone/subscription setup, unlike boot(). Call this on foreground:
    // entries logged just before the app was backgrounded may never have triggered the
    // 1.5s debounce observer, so without this they sit un-uploaded (localEntries > uploadedIDs)
    // and the partner never sees them. This closes that gap.
    func pushPendingChanges() async {
        guard let ds = dataStore else { return }
        await performOutboundSync(ds.entries)
    }

    // Serialized outbound sync — the ONLY path that runs new/deleted/edited uploads. The guard
    // ensures one pass completes (and persists fingerprints/uploadedIDs) before the next starts,
    // so concurrent triggers can't clobber saved state and re-trigger the full-history storm.
    private func performOutboundSync(_ entries: [EntryWrapper]) async {
        guard SyncStateManager.shared.isPro else {
            return
        }
        guard !isSyncingOutbound else {
            return
        }
        isSyncingOutbound = true
        defer { isSyncingOutbound = false }
        await syncNewEntries(entries)
        await syncDeletedEntries(entries)
        await syncEditedEntries(entries)
    }

    // ─── Inbound Sync (iCloud → App) ───────────────────────────────────────

    // Called when a silent push arrives OR when the app comes to the foreground.
    // Owner fetches from privateDB; participant fetches from sharedDB.
    // Foreground / pull-to-refresh entry point. For a PARTICIPANT, this first clears the shared
    // zone token so the fetch returns ALL records — because CloudKit's shared-database delta feed
    // does NOT reliably report the OWNER's edits to existing records to the participant. A full
    // re-fetch catches them, and it's cheap now: the normalized fingerprint means only entries
    // whose content actually changed get re-applied (no storm, no churn). The frequent 60s timer
    // still uses the cheap delta — this fuller fetch only runs on foreground and manual refresh.
    func fetchOnForeground() async {
        if SyncStateManager.shared.isParticipant {
            clearSharedZoneTokens()
        }
        await fetchChanges()
    }

    func fetchChanges() async {
        guard SyncStateManager.shared.isPro, let dataStore else { return }
        // Serialize fetches — overlapping inbound applies create duplicate entries.
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        SyncStateManager.shared.markSyncing()

        if SyncStateManager.shared.isParticipant {
            await fetchSharedChanges(into: dataStore)
        } else {
            await fetchPrivateChanges(into: dataStore)
        }
    }

    // Owner path: fetch from the private zone we created.
    // 📖 SWIFT CONCEPT: CKFetchRecordZoneChangesOperation
    // Instead of "give me ALL records", this says "give me only what changed
    // since my last bookmark (serverChangeToken)." Efficient and battery-friendly.
    private func fetchPrivateChanges(into dataStore: DataStore) async {
        ckLog("[CloudKit] fetchPrivateChanges: starting, token=\(serverChangeToken != nil ? "exists" : "nil")")
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = serverChangeToken

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zone.zoneID],
            configurationsByRecordZoneID: [zone.zoneID: config]
        )

        var inboundEntries: [EntryWrapper] = []
        var deletedRecordNames: [String] = []

        operation.recordWasChangedBlock = { [weak self] _, result in
            guard let self else { return }
            if case .success(let record) = result,
               let entry = makeEntry(from: record) {
                inboundEntries.append(entry)
            }
        }

        // Fires when the partner deleted an entry we still have locally.
        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            deletedRecordNames.append(recordID.recordName)
        }

        operation.recordZoneFetchResultBlock = { [weak self] _, result in
            guard let self else { return }
            if case .success(let (token, _, _)) = result {
                self.serverChangeToken = token
            }
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.fetchRecordZoneChangesResultBlock = { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                privateDB.add(operation)
            }

            // Apply remote deletions (partner deleted an entry on their device).
            for recordName in deletedRecordNames {
                if let uuid = UUID(uuidString: recordName),
                   let entry = dataStore.entries.first(where: { $0.id == uuid }) {
                    dataStore.deleteEntry(entry)
                    var uploaded = loadUploadedIDs()
                    uploaded.remove(recordName)
                    saveUploadedIDs(uploaded)
                    ckLog("[CloudKit] fetchPrivateChanges: applied remote deletion for \(recordName)")
                }
            }

            ckLog("[CloudKit] fetchPrivateChanges: received \(inboundEntries.count) new record(s) from privateDB")
            if !inboundEntries.isEmpty {
                let myUploadedIDs = loadUploadedIDs()
                let fromPartner = inboundEntries.filter { !myUploadedIDs.contains($0.id.uuidString) }
                markPartnerEntries(fromPartner)

                // Handle inbound edits: applyInboundEntries() only ADDS new UUIDs, so for an
                // entry that already exists locally we must replace it ourselves. EntryWrapper
                // is Equatable — compare the decoded content directly. If it differs (partner
                // edited time/oz/notes) delete the local copy so the updated version is re-added
                // below. Identical entries are left untouched — no churn, no migration storm.
                isApplyingInboundEdits = true
                for entry in inboundEntries {
                    if let existing = dataStore.entries.first(where: { $0.id == entry.id }),
                       entryFingerprint(existing) != entryFingerprint(entry) {
                        dataStore.deleteEntry(existing)
                        ckLog("[CloudKit] fetchPrivateChanges: applying inbound edit for \(entry.id)")
                    }
                }
                isApplyingInboundEdits = false

                dataStore.applyInboundEntries(inboundEntries)
                var uploaded = myUploadedIDs
                for entry in inboundEntries { uploaded.insert(entry.id.uuidString) }
                saveUploadedIDs(uploaded)
                // Save fingerprints for ALL inbound entries — new AND edited.
                // Without this, an entry logged on Phone 2 arrives here with no fingerprint.
                // If Phone 1 then edits it, syncEditedEntries sees "no fingerprint → initialise"
                // and silently skips the re-upload on the very first edit.
                var fps = loadFingerprints()
                for entry in inboundEntries { fps[entry.id.uuidString] = entryFingerprint(entry) }
                saveFingerprints(fps)
            }
            SyncStateManager.shared.markSynced()

        } catch {
            ckLog("[CloudKit] fetchPrivateChanges: FAILED — \(error.localizedDescription)")
            SyncStateManager.shared.markError("Fetch failed: \(error.localizedDescription)")
        }
    }

    // Participant path: mom's entries live in her zone inside our sharedDB.
    // We discover the zone by listing all shared zones — we don't know the
    // owner's iCloud record name upfront, so we can't hard-code the zone ID.
    private func fetchSharedChanges(into dataStore: DataStore) async {
        do {
            let sharedZones = try await sharedDB.allRecordZones()
            ckLog("[CloudKit] fetchSharedChanges: allRecordZones returned \(sharedZones.count) zone(s)")
            guard !sharedZones.isEmpty else {
                if SyncStateManager.shared.hasAcceptedShare {
                    // User genuinely joined — empty zones may be transient (CloudKit can take
                    // 5-45s to propagate a newly created zone). Count consecutive misses:
                    // after 3 in a row the share was most likely revoked by the owner.
                    consecutiveEmptyZones += 1
                    ckLog("[CloudKit] fetchSharedChanges: zones empty, hasAcceptedShare=true (streak: \(consecutiveEmptyZones))")
                    if consecutiveEmptyZones >= 3 {
                        SyncStateManager.shared.markError("Partner may have disconnected — open Partner Sync to check")
                    } else {
                        SyncStateManager.shared.markIdle()
                    }
                } else {
                    SyncStateManager.shared.isParticipant = false
                    SyncStateManager.shared.isPartnerConnected = false
                    SyncStateManager.shared.hasPartnerShare = false
                    SyncStateManager.shared.deactivatePro()
                    SyncStateManager.shared.markIdle()
                }
                return
            }
            consecutiveEmptyZones = 0  // zones found — streak broken, reset counter

            var inboundEntries: [EntryWrapper] = []
            var deletedRecordNames: [String] = []
            // Every record ID the fetch reported present, whether or not it decoded. Used ONLY on a
            // full (tokenless) fetch to reconcile owner-side deletions — CloudKit does not fire
            // recordWithIDWasDeletedBlock when there is no prior token.
            var fetchedRecordIDs = Set<String>()
            // True only if EVERY shared zone started with no token (a full fetch). A full fetch's
            // result set is authoritative; a delta fetch's is not, so we only prune on a full fetch.
            var isFullFetch = true

            for sharedZone in sharedZones {
                let zoneID = sharedZone.zoneID
                let priorToken = loadSharedToken(for: zoneID)
                if priorToken != nil { isFullFetch = false }
                let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
                config.previousServerChangeToken = priorToken

                let operation = CKFetchRecordZoneChangesOperation(
                    recordZoneIDs: [zoneID],
                    configurationsByRecordZoneID: [zoneID: config]
                )

                operation.recordWasChangedBlock = { [weak self] _, result in
                    guard let self else { return }
                    if case .success(let record) = result {
                        fetchedRecordIDs.insert(record.recordID.recordName)
                        if let entry = makeEntry(from: record) {
                            inboundEntries.append(entry)
                        }
                    }
                }

                // Fires when the owner deleted an entry we still have locally.
                operation.recordWithIDWasDeletedBlock = { recordID, _ in
                    deletedRecordNames.append(recordID.recordName)
                }

                operation.recordZoneFetchResultBlock = { [weak self] fetchedZoneID, result in
                    guard let self else { return }
                    if case .success(let (token, _, _)) = result {
                        self.saveSharedToken(token, for: fetchedZoneID)
                    }
                }

                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    operation.fetchRecordZoneChangesResultBlock = { result in
                        switch result {
                        case .success: continuation.resume()
                        case .failure(let error): continuation.resume(throwing: error)
                        }
                    }
                    sharedDB.add(operation)
                }
            }

            // Apply remote deletions (owner deleted an entry on their device).
            for recordName in deletedRecordNames {
                if let uuid = UUID(uuidString: recordName),
                   let entry = dataStore.entries.first(where: { $0.id == uuid }) {
                    dataStore.deleteEntry(entry)
                    var uploaded = loadUploadedIDs()
                    uploaded.remove(recordName)
                    saveUploadedIDs(uploaded)
                    ckLog("[CloudKit] fetchSharedChanges: applied remote deletion for \(recordName)")
                }
            }

            // Full-fetch deletion reconciliation. A tokenless full fetch returns the authoritative
            // set of records in the shared zone but does NOT fire recordWithIDWasDeletedBlock, so an
            // owner deletion made while this device was backgrounded is never removed by the delete
            // block above (foreground + pull-to-refresh clear the token → full fetch → the delete is
            // missed and the entry lingers forever). Safely prune: remove local entries we KNOW were
            // on the server (present in uploadedIDs) that are now absent from the full fetch. Entries
            // created on THIS device but not yet uploaded aren't in uploadedIDs, so they're preserved.
            // Guarded by non-empty fetchedRecordIDs so a transient empty response can never wipe all.
            if isFullFetch && !fetchedRecordIDs.isEmpty {
                let uploaded = loadUploadedIDs()
                let localIDs = Set(dataStore.entries.map { $0.id.uuidString })
                let deletedOnServer = uploaded.intersection(localIDs).subtracting(fetchedRecordIDs)
                if !deletedOnServer.isEmpty {
                    isApplyingInboundEdits = true
                    for idStr in deletedOnServer {
                        if let uuid = UUID(uuidString: idStr),
                           let entry = dataStore.entries.first(where: { $0.id == uuid }) {
                            dataStore.deleteEntry(entry)
                        }
                    }
                    isApplyingInboundEdits = false
                    var remaining = loadUploadedIDs()
                    deletedOnServer.forEach { remaining.remove($0) }
                    saveUploadedIDs(remaining)
                    var fps = loadFingerprints()
                    deletedOnServer.forEach { fps.removeValue(forKey: $0) }
                    saveFingerprints(fps)
                    ckLog("[CloudKit] fetchSharedChanges: reconciled \(deletedOnServer.count) owner-deleted entr(ies) from full fetch")
                }
            }

            ckLog("[CloudKit] fetchSharedChanges: received \(inboundEntries.count) new record(s) from sharedDB")
            if !inboundEntries.isEmpty {
                markPartnerEntries(inboundEntries)

                // Same inbound-edit handling as fetchPrivateChanges: EntryWrapper is Equatable,
                // so compare decoded content directly and only replace when it actually differs.
                isApplyingInboundEdits = true
                for entry in inboundEntries {
                    if let existing = dataStore.entries.first(where: { $0.id == entry.id }),
                       entryFingerprint(existing) != entryFingerprint(entry) {
                        dataStore.deleteEntry(existing)
                        ckLog("[CloudKit] fetchSharedChanges: applying inbound edit for \(entry.id)")
                    }
                }
                isApplyingInboundEdits = false

                // Same save-order fix as fetchPrivateChanges: apply locally first,
                // then mark as uploaded, so a crash between the two is recoverable.
                dataStore.applyInboundEntries(inboundEntries)
                var uploaded = loadUploadedIDs()
                for entry in inboundEntries { uploaded.insert(entry.id.uuidString) }
                saveUploadedIDs(uploaded)
                // Same fingerprint fix as fetchPrivateChanges: save for ALL inbound entries
                // so edits made on this device after receiving are detected immediately.
                var fps = loadFingerprints()
                for entry in inboundEntries { fps[entry.id.uuidString] = entryFingerprint(entry) }
                saveFingerprints(fps)
            }
            SyncStateManager.shared.markSynced()

        } catch {
            ckLog("[CloudKit] fetchSharedChanges: FAILED — \(error.localizedDescription)")
            SyncStateManager.shared.markError("Fetch failed: \(error.localizedDescription)")
        }
    }

    // ─── Record ↔ EntryWrapper Conversion ─────────────────────────────────

    // 📖 SWIFT CONCEPT: CKRecord
    // A CKRecord is like a row in a spreadsheet stored in iCloud.
    // Each row has a unique ID (the entry's UUID) and named fields (entryData, etc.).
    //
    // We store the WHOLE entry as JSON in one field.
    // Why not one field per property? Because adding a new property to FeedingEntry
    // would require updating the CloudKit schema AND this mapping code. One JSON field
    // means the schema never needs to change.

    // Writes an entry's fields onto a CKRecord. Used both when CREATING a fresh record
    // (makeRecord) and when MODIFYING an existing server record fetched for an edit
    // (uploadEdited) — so a single place defines the record shape. Returns false if the
    // entry can't be encoded.
    @discardableResult
    private func applyEntryFields(_ entry: EntryWrapper, to record: CKRecord) -> Bool {
        guard let jsonData = try? JSONEncoder().encode(entry),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return false
        }
        record["entryData"]      = jsonString as CKRecordValue
        record["entryTimestamp"] = entry.timestamp as CKRecordValue
        record["schemaVersion"]  = 1 as CKRecordValue
        switch entry {
        case .feeding: record["entryType"] = "feeding" as CKRecordValue
        case .diaper:  record["entryType"] = "diaper"  as CKRecordValue
        }
        return true
    }

    private func makeRecord(from entry: EntryWrapper, zoneID: CKRecordZone.ID) -> CKRecord? {
        // recordName = the entry's UUID. CloudKit uses this as the primary key.
        // Two devices saving the same UUID = only one record (natural dedup).
        let recordID = CKRecord.ID(recordName: entry.id.uuidString, zoneID: zoneID)
        let record   = CKRecord(recordType: kRecordType, recordID: recordID)
        return applyEntryFields(entry, to: record) ? record : nil
    }

    private func makeEntry(from record: CKRecord) -> EntryWrapper? {
        guard let jsonString = record["entryData"] as? String,
              let jsonData   = jsonString.data(using: .utf8),
              let entry      = try? JSONDecoder().decode(EntryWrapper.self, from: jsonData) else {
            ckLog("[CloudKit] makeEntry: JSON decode failed for record \(record.recordID.recordName)")
            return nil
        }
        return entry
    }

    // ─── Uploaded IDs Persistence ──────────────────────────────────────────

    // Keeps a local record of which UUIDs are already in iCloud so we never
    // double-upload and don't need to query CloudKit to check.

    private let kUploadedIDsKey = "mommyslog.uploadedEntryIDs"

    private func loadUploadedIDs() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: kUploadedIDsKey) ?? []
        return Set(array)
    }

    private func saveUploadedIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: kUploadedIDsKey)
    }

    // ─── Entry Fingerprints ────────────────────────────────────────────────
    // Tracks a short hash of each uploaded entry's JSON content.
    // When the Combine observer fires, we compare current content against stored hashes
    // to detect edits (same UUID, different content) and re-upload only changed entries.

    private let kEntryFingerprintsKey = "mommyslog.entryFingerprints"

    private func loadFingerprints() -> [String: String] {
        (UserDefaults.standard.object(forKey: kEntryFingerprintsKey) as? [String: String]) ?? [:]
    }

    private func saveFingerprints(_ fps: [String: String]) {
        UserDefaults.standard.set(fps, forKey: kEntryFingerprintsKey)
    }

    // Deterministic fingerprint of an entry's FULL content (SHA-256 of its JSON).
    //
    // ⚠️ Must hash the ENTIRE encoded entry, not a prefix. An earlier version used
    // the first 16 base-64 chars (~12 JSON bytes) which only covered the wrapper key
    // and the start of the UUID — edits to notes, oz, duration, or timestamp live
    // later in the JSON and produced an IDENTICAL fingerprint, so edits were never
    // detected (neither uploaded by the editor nor applied by the receiver).
    //
    // SHA-256 over the same JSON the record stores in `entryData` is stable across
    // launches AND devices: makeEntry() decodes that same JSON string back, so the
    // sender's hash and the receiver's hash match byte-for-byte.
    private func entryFingerprint(_ entry: EntryWrapper) -> String {
        // Stable, NORMALIZED fingerprint of an entry's MEANINGFUL content. Timestamps are rounded
        // to whole seconds and doubles formatted to fixed decimals, so the JSON round-trip through
        // CloudKit (which can shift sub-second Date precision) can NEVER produce a different
        // fingerprint for the same logical entry. Hashing raw JSON did exactly that and caused a
        // perpetual "everything edited" re-upload storm. Do NOT go back to hashing raw bytes.
        switch entry {
        case .feeding(let f):
            let ts   = Int(f.timestamp.timeIntervalSince1970.rounded())
            let dur  = Int(f.duration.rounded())
            let amt  = f.amount.map { String(format: "%.2f", $0) } ?? "-"
            let side = f.side.map { "\($0)" } ?? "-"
            return "F|\(ts)|\(f.type)|\(side)|\(dur)|\(amt)|\(f.notes ?? "")"
        case .diaper(let d):
            let ts = Int(d.timestamp.timeIntervalSince1970.rounded())
            return "D|\(ts)|\(d.type)|\(d.notes ?? "")"
        }
    }

    // ─── Partner Entry Tracking ────────────────────────────────────────────
    // Tracks which entry UUIDs arrived via inbound sync (i.e. were logged by
    // the other device). Used by ActivityRowView to show a partner badge.
    // Does NOT modify any model — purely an external lookup table.

    private let kPartnerEntryIDsKey = "mommyslog.partnerEntryIDs"

    func isPartnerEntry(_ id: UUID) -> Bool {
        let ids = UserDefaults.standard.stringArray(forKey: kPartnerEntryIDsKey) ?? []
        return ids.contains(id.uuidString)
    }

    private func markPartnerEntries(_ entries: [EntryWrapper]) {
        guard !entries.isEmpty else { return }
        var ids = Set(UserDefaults.standard.stringArray(forKey: kPartnerEntryIDsKey) ?? [])
        entries.forEach { ids.insert($0.id.uuidString) }
        UserDefaults.standard.set(Array(ids), forKey: kPartnerEntryIDsKey)
    }

    // ─── Shared Zone Token Persistence ────────────────────────────────────
    // Each shared zone gets its own change token, keyed by zone record name.

    private func loadSharedToken(for zoneID: CKRecordZone.ID) -> CKServerChangeToken? {
        let key = "mommyslog.sharedToken.\(zoneID.ownerName).\(zoneID.zoneName)"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveSharedToken(_ token: CKServerChangeToken?, for zoneID: CKRecordZone.ID) {
        let key = "mommyslog.sharedToken.\(zoneID.ownerName).\(zoneID.zoneName)"
        if let token,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // Starts a 60-second repeating timer that calls fetchChanges().
    // Handles the case where both phones are in the foreground simultaneously —
    // scenePhase doesn't fire in that scenario so silent push is the only trigger,
    // which iOS can throttle. The timer guarantees a maximum 60s sync lag.
    private func startPeriodicRefresh() {
        refreshTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.fetchChanges() }
            }
    }

    // Clears change tokens so the next fetch re-downloads ALL records from iCloud.
    // Owner (Phone 1) → clears private DB token.
    // Participant (Phone 2) → clears shared zone tokens (same as clearSharedZoneTokens).
    // Also clears partnerEntryIDs so partner badges are re-applied on full fetch.
    func forceRefetchAll() {
        ckLog("[CloudKit] forceRefetchAll: clearing tokens — next fetch will re-download everything")
        if SyncStateManager.shared.isParticipant {
            clearSharedZoneTokens()
        } else {
            serverChangeToken = nil
        }
        UserDefaults.standard.removeObject(forKey: kPartnerEntryIDsKey)
        Task { await fetchChanges() }
    }

    // Wipes all shared zone change tokens so the next fetchSharedChanges()
    // returns every record from scratch instead of only incremental deltas.
    // Call this when Phone 2 first accepts the share.
    func clearSharedZoneTokens() {
        let prefix = "mommyslog.sharedToken."
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
        // Also clear partner entry IDs so the next full fetch re-marks them correctly.
        UserDefaults.standard.removeObject(forKey: kPartnerEntryIDsKey)
    }
}