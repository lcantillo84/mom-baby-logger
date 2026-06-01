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
            } else {
                try await setupZoneIfNeeded()
                try await setupSubscriptionIfNeeded()
                // Eagerly upload any local entries not yet in iCloud.
                // Catches entries logged before Pro was activated or before the share was created.
                if let ds = dataStore { await syncNewEntries(ds.entries) }
            }
            observeDataStore()
            await fetchChanges()
            await retryPending()
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
                guard !dataStore.isApplyingInboundSync else { return }
                Task { await self.syncNewEntries(newEntries) }
            }
            .store(in: &cancellables)  // keep the subscription alive
    }

    // ─── Outbound Sync (App → iCloud) ──────────────────────────────────────

    // Figures out which entries haven't been uploaded yet and sends them.
    // Also retries anything that failed before.
    private func syncNewEntries(_ currentEntries: [EntryWrapper]) async {
        let uploadedIDs = loadUploadedIDs()
        let toUpload = currentEntries.filter { !uploadedIDs.contains($0.id.uuidString) }
        print("[CloudKit] syncNewEntries: total=\(currentEntries.count) alreadyUploaded=\(uploadedIDs.count) toUpload=\(toUpload.count)")
        guard !toUpload.isEmpty else { return }

        SyncStateManager.shared.markSyncing()
        await upload(entries: toUpload)
    }

    // Does the actual CKRecord save. Marks entries as uploaded or queues for retry.
    // Participants write to sharedDB (mom's zone); owner writes to privateDB.
    // CloudKit recommends batches of ≤400 records per operation.
    // Sending 1000+ records in one shot can trigger limitExceeded errors.
    private let kUploadBatchSize = 400

    private func upload(entries toUpload: [EntryWrapper]) async {
        let (targetDB, targetZoneID) = await resolveUploadTarget()
        let dbLabel = SyncStateManager.shared.isParticipant ? "sharedDB" : "privateDB"

        var records: [CKRecord] = []
        for entry in toUpload {
            if let record = makeRecord(from: entry, zoneID: targetZoneID) {
                records.append(record)
            }
        }
        guard !records.isEmpty else { return }

        // Split into batches so we never exceed CloudKit's per-operation record limit.
        let batches = stride(from: 0, to: records.count, by: kUploadBatchSize).map {
            Array(records[$0..<min($0 + kUploadBatchSize, records.count)])
        }
        print("[CloudKit] upload: \(records.count) record(s) → \(batches.count) batch(es) to \(dbLabel) zone=\(targetZoneID.zoneName)")

        var successCount = 0
        for (i, batch) in batches.enumerated() {
            let operation = CKModifyRecordsOperation(recordsToSave: batch, recordIDsToDelete: nil)
            operation.savePolicy = .ifServerRecordUnchanged

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
                successCount += batch.count
                print("[CloudKit] upload: batch \(i+1)/\(batches.count) SUCCESS (\(batch.count) records)")
            } catch {
                print("[CloudKit] upload: batch \(i+1)/\(batches.count) FAILED — \(error.localizedDescription)")
                // Queue the entries in this failed batch for retry.
                let failedEntries = toUpload.filter { entry in
                    batch.contains { $0.recordID.recordName == entry.id.uuidString }
                }
                for entry in failedEntries { pendingRetryIDs.insert(entry.id.uuidString) }
                SyncStateManager.shared.markError("Upload failed: \(error.localizedDescription)")
                return
            }
        }

        // All batches succeeded — mark every entry as uploaded.
        var uploaded = loadUploadedIDs()
        for entry in toUpload {
            uploaded.insert(entry.id.uuidString)
            pendingRetryIDs.remove(entry.id.uuidString)
        }
        saveUploadedIDs(uploaded)
        print("[CloudKit] upload: ALL \(successCount) record(s) saved to \(dbLabel)")
        SyncStateManager.shared.markSynced()
    }

    // Returns the right (database, zoneID) pair for uploads.
    // Participant → sharedDB using the discovered shared zone.
    // Owner       → privateDB using our own zone.
    private func resolveUploadTarget() async -> (CKDatabase, CKRecordZone.ID) {
        guard SyncStateManager.shared.isParticipant else {
            return (privateDB, zone.zoneID)
        }
        if let sharedZone = try? await sharedDB.allRecordZones()
            .first(where: { $0.zoneID.zoneName == kZoneName }) {
            return (sharedDB, sharedZone.zoneID)
        }
        // Fallback: no shared zone found yet — write to private as a safety net.
        return (privateDB, zone.zoneID)
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

    // ─── Inbound Sync (iCloud → App) ───────────────────────────────────────

    // Called when a silent push arrives OR when the app comes to the foreground.
    // Owner fetches from privateDB; participant fetches from sharedDB.
    func fetchChanges() async {
        guard SyncStateManager.shared.isPro, let dataStore else { return }
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
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        config.previousServerChangeToken = serverChangeToken

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zone.zoneID],
            configurationsByRecordZoneID: [zone.zoneID: config]
        )

        var inboundEntries: [EntryWrapper] = []

        operation.recordWasChangedBlock = { [weak self] _, result in
            guard let self else { return }
            if case .success(let record) = result,
               let entry = makeEntry(from: record) {
                inboundEntries.append(entry)
            }
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

            if !inboundEntries.isEmpty {
                // Entries from fetchPrivateChanges that we didn't upload ourselves
                // were logged by the partner device — mark them for UI display.
                let myUploadedIDs = loadUploadedIDs()
                let fromPartner = inboundEntries.filter { !myUploadedIDs.contains($0.id.uuidString) }
                markPartnerEntries(fromPartner)
                var uploaded = myUploadedIDs
                for entry in inboundEntries { uploaded.insert(entry.id.uuidString) }
                saveUploadedIDs(uploaded)
                dataStore.applyInboundEntries(inboundEntries)
            }
            SyncStateManager.shared.markSynced()

        } catch {
            SyncStateManager.shared.markError("Fetch failed: \(error.localizedDescription)")
        }
    }

    // Participant path: mom's entries live in her zone inside our sharedDB.
    // We discover the zone by listing all shared zones — we don't know the
    // owner's iCloud record name upfront, so we can't hard-code the zone ID.
    private func fetchSharedChanges(into dataStore: DataStore) async {
        do {
            let sharedZones = try await sharedDB.allRecordZones()
            print("[CloudKit] fetchSharedChanges: allRecordZones returned \(sharedZones.count) zone(s)")
            guard !sharedZones.isEmpty else {

                // Empty zones could mean Phone 1 revoked the share, OR it could be a
                // transient CloudKit propagation delay. If hasAcceptedShare is true the user
                // genuinely joined — don't wipe their Pro/participant state on a single empty
                // response, because doing so permanently breaks sync until they manually
                // navigate to PartnerSyncView (the only place restoreParticipantStateIfNeeded
                // is called). Only clear state when we're sure they never accepted.
                if !SyncStateManager.shared.hasAcceptedShare {
                    SyncStateManager.shared.isParticipant = false
                    SyncStateManager.shared.isPartnerConnected = false
                    SyncStateManager.shared.hasPartnerShare = false
                    SyncStateManager.shared.deactivatePro()
                }
                SyncStateManager.shared.markIdle()
                return
            }

            var inboundEntries: [EntryWrapper] = []

            for sharedZone in sharedZones {
                let zoneID = sharedZone.zoneID
                let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
                config.previousServerChangeToken = loadSharedToken(for: zoneID)

                let operation = CKFetchRecordZoneChangesOperation(
                    recordZoneIDs: [zoneID],
                    configurationsByRecordZoneID: [zoneID: config]
                )

                operation.recordWasChangedBlock = { [weak self] _, result in
                    guard let self else { return }
                    if case .success(let record) = result,
                       let entry = makeEntry(from: record) {
                        inboundEntries.append(entry)
                    }
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

            print("[CloudKit] fetchSharedChanges: received \(inboundEntries.count) new record(s) from sharedDB")
            if !inboundEntries.isEmpty {
                markPartnerEntries(inboundEntries)
                var uploaded = loadUploadedIDs()
                for entry in inboundEntries { uploaded.insert(entry.id.uuidString) }
                saveUploadedIDs(uploaded)
                dataStore.applyInboundEntries(inboundEntries)
            }
            SyncStateManager.shared.markSynced()

        } catch {
            print("[CloudKit] fetchSharedChanges: FAILED — \(error.localizedDescription)")
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

    private func makeRecord(from entry: EntryWrapper, zoneID: CKRecordZone.ID) -> CKRecord? {
        guard let jsonData = try? JSONEncoder().encode(entry),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        // recordName = the entry's UUID. CloudKit uses this as the primary key.
        // Two devices saving the same UUID = only one record (natural dedup).
        let recordID = CKRecord.ID(recordName: entry.id.uuidString, zoneID: zoneID)
        let record   = CKRecord(recordType: kRecordType, recordID: recordID)

        record["entryData"]      = jsonString as CKRecordValue
        record["entryTimestamp"] = entry.timestamp as CKRecordValue
        record["schemaVersion"]  = 1 as CKRecordValue

        switch entry {
        case .feeding: record["entryType"] = "feeding" as CKRecordValue
        case .diaper:  record["entryType"] = "diaper"  as CKRecordValue
        }

        return record
    }

    private func makeEntry(from record: CKRecord) -> EntryWrapper? {
        guard let jsonString = record["entryData"] as? String,
              let jsonData   = jsonString.data(using: .utf8),
              let entry      = try? JSONDecoder().decode(EntryWrapper.self, from: jsonData) else {
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