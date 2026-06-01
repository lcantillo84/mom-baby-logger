//
//  SharingManager.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// This handles the "invite your partner" flow.
//
// Mom taps "Invite Partner" → iOS shows a share sheet (same one
// you use to share a photo) → she sends a link via iMessage.
//
// Partner taps the link → iOS asks "Accept access to Mommy's Log?"
// → Partner's app opens and downloads all of mom's entries.
//
// This file creates, manages, and revokes that shared access.
// The sharing is built on Apple's CKShare — zero custom servers needed.
// ─────────────────────────────────────────────────────────────

import Combine
import CloudKit
import UIKit

// File-level so it's callable from inside closures without `self`.
// Compiles out completely in App Store / Release builds.
// To re-enable in Release: change `#if DEBUG` to `if true`.
private func smLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}

@MainActor
class SharingManager: ObservableObject {

    static let shared = SharingManager()

    // The CKShare object represents the "invitation link."
    // If non-nil, mom has an active share. Nil = not shared yet.
    @Published var activeShare: CKShare?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private lazy var container: CKContainer = {
        CKContainer(identifier: kContainerID)
    }()

    private lazy var privateDB: CKDatabase = {
        container.privateCloudDatabase
    }()

    private lazy var sharedDB: CKDatabase = {
        container.sharedCloudDatabase
    }()

    private lazy var zone: CKRecordZone = {
        CKRecordZone(zoneName: kZoneName)
    }()

    // UserDefaults key to remember the share's record name between launches.
    private let kShareRecordNameKey = "mommyslog.shareRecordName"

    // Share architecture version. v1 = hierarchy-based (broken — entries not exposed to
    // participants). v2 = zone-based (correct — all records in the zone are shared).
    private let kShareVersionKey     = "mommyslog.shareVersion"
    private let kCurrentShareVersion = 2

    private init() {}

    // ─── Load Existing Share ───────────────────────────────────────────────

    // Call this when PartnerSyncView appears to show current share status.
    func loadExistingShare() async {
        isLoading = true
        defer { isLoading = false }

        // If on an old share version, treat as no share. Loading the broken hierarchy-based
        // share would show "Invite Sent / Waiting" for an invite that could never work.
        // The next time the user taps Invite, fetchOrCreateShare() migrates to zone-based.
        let storedVersion = UserDefaults.standard.integer(forKey: kShareVersionKey)
        guard storedVersion >= kCurrentShareVersion else {
            activeShare = nil
            SyncStateManager.shared.isPartnerConnected = false
            return
        }

        guard let savedName = UserDefaults.standard.string(forKey: kShareRecordNameKey) else {
            activeShare = nil
            return
        }

        let recordID = CKRecord.ID(recordName: savedName, zoneID: zone.zoneID)

        do {
            let record = try await privateDB.record(for: recordID)
            activeShare = record as? CKShare
            // Update Phone 1's connection status by checking actual participant acceptance.
            // Without this, Phone 1 would stay stuck on "Waiting for partner to accept"
            // even after the partner taps the link and joins.
            if let share = activeShare {
                let hasAccepted = share.participants.contains {
                    $0.role != .owner && $0.acceptanceStatus == .accepted
                }
                SyncStateManager.shared.isPartnerConnected = hasAccepted
            }
        } catch {
            // Share was deleted from iCloud (e.g. partner revoked it or iCloud cleanup).
            activeShare = nil
            UserDefaults.standard.removeObject(forKey: kShareRecordNameKey)
        }
    }

    // ─── Create Share & Show Share Sheet ──────────────────────────────────

    // 📖 SWIFT CONCEPT: UIActivityViewController
    // This is the standard iOS share sheet — the popup that shows iMessage,
    // Mail, AirDrop, etc. Apple provides it; we just configure and present it.
    //
    // We pass a CKShareMetadata object. iOS recognises CloudKit shares and
    // adds a special "Accept" option when the recipient opens the link.

    func presentShareSheet(from viewController: UIViewController) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                errorMessage = iCloudAccountMessage(for: status)
                return
            }
        } catch {
            errorMessage = "iCloud is not available. Please check your iCloud settings and try again."
            return
        }

        do {
            let share = try await fetchOrCreateShare()
            activeShare = share

            let sharingController = UICloudSharingController(share: share, container: container)
            sharingController.delegate = ShareDelegate.shared
            sharingController.availablePermissions = [.allowReadWrite]

            await MainActor.run {
                // Traverse to the topmost presented VC — presenting from root fails
                // silently when the app is several navigation levels deep.
                var presenter = viewController
                while let top = presenter.presentedViewController { presenter = top }
                presenter.present(sharingController, animated: true)
            }

        } catch let ckError as CKError where ckError.code == .notAuthenticated {
            errorMessage = "Partner Sync requires iCloud. Go to Settings → [your name] → iCloud and make sure iCloud Drive is turned on for this app."
        } catch let ckError as CKError {
            errorMessage = "iCloud error (\(ckError.code.rawValue)): \(ckError.localizedDescription)"
        } catch {
            errorMessage = "Could not create share: \(error.localizedDescription)"
        }
    }

    private func iCloudAccountMessage(for status: CKAccountStatus) -> String {
        switch status {
        case .noAccount:
            return "No iCloud account found. Go to Settings → Sign in to your iPhone to set up iCloud."
        case .restricted:
            return "iCloud is restricted on this device (parental controls or MDM). Partner Sync is unavailable."
        case .couldNotDetermine:
            return "Could not reach iCloud. Check your internet connection and try again."
        case .temporarilyUnavailable:
            return "iCloud is temporarily unavailable. Please try again in a moment."
        default:
            return "iCloud is not available. Please check your iCloud settings."
        }
    }

    // ─── Prepare Share (returns CKShare for SwiftUI sheet presentation) ──────

    func prepareShare() async -> CKShare? {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                errorMessage = iCloudAccountMessage(for: status)
                return nil
            }
            let share = try await fetchOrCreateShare()
            activeShare = share
            return share
        } catch let ckError as CKError where ckError.code == .notAuthenticated {
            errorMessage = "Partner Sync requires iCloud. Go to Settings → [your name] → iCloud and make sure iCloud Drive is turned on for this app."
            return nil
        } catch let ckError as CKError {
            errorMessage = "iCloud error (\(ckError.code.rawValue)): \(ckError.localizedDescription)"
            return nil
        } catch {
            errorMessage = "Could not prepare share: \(error.localizedDescription)"
            return nil
        }
    }

    // ─── Get Share URL ────────────────────────────────────────────────────

    // Returns the invite URL for display in a SwiftUI sheet.
    // CloudKit assigns the URL server-side. fetchOrCreateShare() tries to capture
    // it from perRecordSaveBlock; if that fails (known CloudKit quirk on some iOS
    // builds) we fetch the saved share back explicitly with full error logging.
    func getShareURL() async -> URL? {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        smLog("[SharingManager] getShareURL: starting")
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                errorMessage = iCloudAccountMessage(for: status)
                return nil
            }

            let share = try await fetchOrCreateShare()
            activeShare = share

            if let url = share.url {
                smLog("[SharingManager] getShareURL: URL from fetchOrCreateShare → \(url)")
                return url
            }

            // URL still nil — fetch the share back from the server.
            // CloudKit sometimes doesn't include the URL in the initial save
            // response for zone-based shares; a separate fetch reliably returns it.
            smLog("[SharingManager] getShareURL: URL nil after fetchOrCreateShare — retrying fetch. recordID=\(share.recordID.recordName)")
            do {
                let fetched = try await privateDB.record(for: share.recordID)
                smLog("[SharingManager] getShareURL: fetched type=\(fetched.recordType) isShare=\(fetched is CKShare)")
                if let fetchedShare = fetched as? CKShare {
                    smLog("[SharingManager] getShareURL: fetchedShare.url=\(String(describing: fetchedShare.url))")
                    activeShare = fetchedShare
                    if let url = fetchedShare.url { return url }
                    smLog("[SharingManager] getShareURL: fetchedShare.url still nil after retry fetch")
                } else {
                    smLog("[SharingManager] getShareURL: retry-fetch cast to CKShare FAILED")
                }
            } catch {
                smLog("[SharingManager] getShareURL: retry-fetch error: \(error)")
            }

            errorMessage = "Could not generate invite link. Check your iCloud connection and try again."
            return nil

        } catch let ckError as CKError where ckError.code == .notAuthenticated {
            errorMessage = "Partner Sync requires iCloud. Go to Settings → [your name] → iCloud and make sure iCloud Drive is turned on for this app."
            return nil
        } catch let ckError as CKError {
            errorMessage = "iCloud error (\(ckError.code.rawValue)): \(ckError.localizedDescription)"
            return nil
        } catch {
            errorMessage = "Could not create invite: \(error.localizedDescription)"
            return nil
        }
    }

    // ─── Revoke / Disconnect Partner ──────────────────────────────────────

    func revokeShare() async {
        guard let share = activeShare else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            // Deleting the CKShare from iCloud immediately removes all access.
            // The partner's device will get a "zone deleted" notification and
            // CloudKitManager will remove the shared data from their device.
            try await privateDB.deleteRecord(withID: share.recordID)
            activeShare = nil
            SyncStateManager.shared.isPartnerConnected = false
            SyncStateManager.shared.hasPartnerShare = false
            SyncStateManager.shared.isParticipant = false
            UserDefaults.standard.removeObject(forKey: kShareRecordNameKey)
        } catch {
            errorMessage = "Could not revoke share: \(error.localizedDescription)"
        }
    }

    // ─── Leave Share (Partner/Nanny Side) ─────────────────────────────────

    // Called when Phone 2 wants to stop accessing the shared log.
    // Clears local state — the owner's share remains active so they can re-invite.
    func leaveShare() async {
        isLoading = true
        defer { isLoading = false }
        SyncStateManager.shared.isParticipant = false
        SyncStateManager.shared.isPartnerConnected = false
        SyncStateManager.shared.hasPartnerShare = false
        SyncStateManager.shared.hasAcceptedShare = false
        SyncStateManager.shared.deactivatePro()
        UserDefaults.standard.removeObject(forKey: kShareRecordNameKey)
        activeShare = nil
    }

    // ─── Join by Pasted URL (fallback for Mac / dev builds) ──────────────────

    // On Mac Catalyst dev builds, the OS doesn't route cloudkit.com share URLs
    // to the app's delegate — acceptShare(metadata:) never fires. This method
    // accepts a share directly from its URL by fetching the metadata itself, so
    // the partner can copy/paste the invite link instead of relying on URL routing.
    func acceptShareByURL(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        smLog("[SharingManager] acceptShareByURL: fetching metadata for \(url)")

        do {
            let metadata: CKShare.Metadata = try await withCheckedThrowingContinuation { cont in
                var captured: CKShare.Metadata?
                let op = CKFetchShareMetadataOperation(shareURLs: [url])
                op.perShareMetadataResultBlock = { _, result in
                    if case .success(let meta) = result { captured = meta }
                }
                op.fetchShareMetadataResultBlock = { result in
                    switch result {
                    case .success:
                        if let meta = captured {
                            cont.resume(returning: meta)
                        } else {
                            cont.resume(throwing: NSError(
                                domain: "SharingManager", code: 0,
                                userInfo: [NSLocalizedDescriptionKey: "No share metadata returned for this URL."]))
                        }
                    case .failure(let e):
                        cont.resume(throwing: e)
                    }
                }
                container.add(op)
            }
            smLog("[SharingManager] acceptShareByURL: metadata fetched — calling acceptShare")
            await acceptShare(metadata: metadata)
        } catch {
            smLog("[SharingManager] acceptShareByURL: error — \(error)")
            errorMessage = "Could not access share link: \(error.localizedDescription)"
        }
    }

    // ─── Accept Incoming Share (Partner Side) ─────────────────────────────

    // Called from AppDelegate+CloudKit when the partner taps the link.
    // Accepts the CloudKit share, then fetches all mom's existing entries.
    func acceptShare(metadata: CKShare.Metadata) async {
        // ⚑ THIS PRINT IS THE FIRST THING THAT RUNS — if you don't see it in the
        // console, the OS never routed the share URL to the app's delegate.
        // On Mac: the link must be clicked in Messages or Mail, NOT opened in Safari.
        smLog("[SharingManager] acceptShare: called — containerID=\(metadata.containerIdentifier)")

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
                op.acceptSharesResultBlock = { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                self.container.add(op)
            }
            smLog("[SharingManager] acceptShare: CKAcceptSharesOperation succeeded")
            SyncStateManager.shared.hasAcceptedShare = true

            // Wait for the shared zone to become visible in sharedDB before setting
            // participant state. CloudKit can take 1-4 seconds to propagate a newly
            // accepted zone. Without this wait, fetchSharedChanges() sees zero zones,
            // mistakes it for a revoked share, and wipes all participant state — making
            // it look like nothing happened ("only the app opens up").
            CloudKitManager.shared.clearSharedZoneTokens()

            // Set participant state BEFORE polling. This way the UI updates immediately
            // so the user sees they are connected even while we wait for zone propagation.
            SyncStateManager.shared.isPartnerConnected = true
            SyncStateManager.shared.hasPartnerShare = true
            SyncStateManager.shared.isParticipant = true
            SyncStateManager.shared.activatePro()
            smLog("[SharingManager] acceptShare: participant state set — polling for zone visibility")

            // Poll for the shared zone to appear in sharedDB. Mac Catalyst zone propagation
            // can take up to 45 seconds; iPhone is usually 1-4 seconds. We poll here rather
            // than calling startSyncAfterJoining() immediately because fetchSharedChanges()
            // inside CloudKitManager sees zero zones and RESETS isParticipant to false,
            // which would undo the state we just set above.
            var zoneReady = false
            for attempt in 1...15 {
                do {
                    let zones = try await sharedDB.allRecordZones()
                    smLog("[SharingManager] acceptShare: attempt \(attempt) — allRecordZones returned \(zones.count) zone(s): \(zones.map { "\($0.zoneID.zoneName)/\($0.zoneID.ownerName)" })")
                    if !zones.isEmpty {
                        zoneReady = true
                        break
                    }
                } catch {
                    smLog("[SharingManager] acceptShare: attempt \(attempt) — allRecordZones THREW: \(error)")
                }
                try? await Task.sleep(for: .seconds(3))
            }

            // Always start sync whether or not the zone was confirmed visible.
            // NOT calling this when polling times out leaves Phone 2 permanently stuck:
            // it has all-true state flags but fetchChanges() never runs this session,
            // and background pushes only call fetchChanges() which idles on empty zones.
            CloudKitManager.shared.startSyncAfterJoining()
            if zoneReady {
                smLog("[SharingManager] acceptShare: zone confirmed — sync started")
            } else {
                smLog("[SharingManager] acceptShare: zone not visible after 45s — sync attempted anyway; fetchSharedChanges() will idle if zone still empty")
            }

        } catch {
            smLog("[SharingManager] acceptShare: error — \(error)")
            errorMessage = "Could not accept share: \(error.localizedDescription)"
        }
    }

    // ─── Restore Participant State After CloudKitManager Reset ─────────────

    // CloudKitManager.fetchSharedChanges() resets isParticipant=false when
    // allRecordZones() returns empty (e.g. zone still propagating on app launch).
    // This method re-applies participant state using the durable hasAcceptedShare
    // sentinel that CloudKitManager never touches.
    func restoreParticipantStateIfNeeded() async {
        let accepted = SyncStateManager.shared.hasAcceptedShare
        smLog("[SharingManager] restoreParticipantStateIfNeeded: hasAcceptedShare=\(accepted) isParticipant=\(SyncStateManager.shared.isParticipant)")
        guard accepted else { return }

        // Always re-assert Pro + participant access — CloudKitManager may have reset them.
        SyncStateManager.shared.isParticipant = true
        SyncStateManager.shared.activatePro()

        let zones = try? await sharedDB.allRecordZones()
        let zoneCount = zones?.count ?? 0
        smLog("[SharingManager] restoreParticipantStateIfNeeded: sharedDB zones=\(zoneCount)")

        if zoneCount > 0 {
            SyncStateManager.shared.isPartnerConnected = true
            SyncStateManager.shared.hasPartnerShare = true
            smLog("[SharingManager] restoreParticipantStateIfNeeded: zones visible — full state restored, triggering sync")
            CloudKitManager.shared.startSyncAfterJoining()
        } else {
            // Zones not yet propagated — state is already set above.
            // Do NOT call startSyncAfterJoining(): fetchSharedChanges() sees
            // empty zones and calls deactivatePro(), undoing everything.
            smLog("[SharingManager] restoreParticipantStateIfNeeded: zones not visible yet — isParticipant+isPro restored, sync deferred until next refresh")
        }
    }

    // ─── Private Helpers ───────────────────────────────────────────────────

    // Ensures MommysLogZone exists before we try to create records in it.
    // CloudKit returns notAuthenticated (confusingly) when writing to a
    // zone that hasn't been created yet.
    private func ensureZoneExists() async throws {
        let op = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            privateDB.add(op)
        }
    }

    // Deletes and recreates MommysLogZone so CloudKit assigns the zoneWideSharing capability.
    // All CloudKit records in the zone are removed, but entries are persisted in DataStore
    // (UserDefaults-backed) and will re-upload automatically on the next sync cycle.
    private func migrateZoneForZoneWideSharing() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordZonesOperation(recordZonesToSave: nil,
                                                  recordZoneIDsToDelete: [zone.zoneID])
            op.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            privateDB.add(op)
        }
        smLog("[SharingManager] migrateZoneForZoneWideSharing: zone deleted")

        // Clear CloudKitManager's state keys so it treats this as a fresh start:
        // – zoneCreated: forces setupZoneIfNeeded() to save the new zone
        // – uploadedEntryIDs: forces syncNewEntries() to re-upload all local entries
        // – serverChangeToken: forces fetchChanges() to pull the full record set
        UserDefaults.standard.removeObject(forKey: "mommyslog.zoneCreated")
        UserDefaults.standard.removeObject(forKey: "mommyslog.uploadedEntryIDs")
        UserDefaults.standard.removeObject(forKey: "mommyslog.serverChangeToken")

        // Recreate the zone — on iOS 15+ this yields a zone with zoneWideSharing.
        try await ensureZoneExists()
        smLog("[SharingManager] migrateZoneForZoneWideSharing: zone recreated with zoneWideSharing")

        // Kick CloudKitManager to re-upload all local entries to the fresh zone.
        CloudKitManager.shared.startSyncAfterJoining()
    }

    private func fetchOrCreateShare() async throws -> CKShare {
        let storedVersion = UserDefaults.standard.integer(forKey: kShareVersionKey)

        smLog("[SharingManager] fetchOrCreateShare: storedVersion=\(storedVersion) currentVersion=\(kCurrentShareVersion) activeShare.url=\(String(describing: activeShare?.url))")

        // Fast path: current-version share already loaded into memory WITH a URL.
        // If URL is nil the share was saved but the URL wasn't captured — don't
        // short-circuit; fall through to re-fetch from CloudKit.
        if storedVersion >= kCurrentShareVersion, let existing = activeShare, existing.url != nil {
            smLog("[SharingManager] fetchOrCreateShare: in-memory fast path, URL=\(existing.url!)")
            if existing.publicPermission != .readWrite {
                existing.publicPermission = .readWrite
                try? await saveUpdatedShare(existing)
            }
            return existing
        }

        // Current version — fetch the saved share from CloudKit by its stored record name.
        // Uses a full do/catch so cast failures and network errors are both logged.
        if storedVersion >= kCurrentShareVersion,
           let savedName = UserDefaults.standard.string(forKey: kShareRecordNameKey) {
            smLog("[SharingManager] fetchOrCreateShare: fetching saved share '\(savedName)' from CloudKit")
            do {
                let record = try await privateDB.record(
                    for: CKRecord.ID(recordName: savedName, zoneID: zone.zoneID))
                smLog("[SharingManager] fetchOrCreateShare: fetched type=\(record.recordType) isShare=\(record is CKShare)")
                if let share = record as? CKShare {
                    smLog("[SharingManager] fetchOrCreateShare: saved share URL=\(String(describing: share.url))")
                    activeShare = share
                    if share.publicPermission != .readWrite {
                        share.publicPermission = .readWrite
                        try? await saveUpdatedShare(share)
                    }
                    return share
                } else {
                    smLog("[SharingManager] fetchOrCreateShare: cast to CKShare FAILED — will recreate")
                }
            } catch {
                smLog("[SharingManager] fetchOrCreateShare: failed to fetch saved share: \(error) — will recreate")
            }
        }

        // ── Migration / first invite ───────────────────────────────────────────
        // Delete any existing old share. The old code used CKShare(rootRecord:) which is a
        // *hierarchy-based* share — it only exposes the ShareRoot record and its explicit
        // children, NOT the Entry records saved by CloudKitManager. That is why Phone 2
        // could accept the invite and see the zone, but found zero entries.
        // CKShare(recordZoneID:) shares ALL records in the zone — the correct type.

        if let existing = activeShare {
            _ = try? await privateDB.deleteRecord(withID: existing.recordID)
            activeShare = nil
        } else if let savedName = UserDefaults.standard.string(forKey: kShareRecordNameKey) {
            _ = try? await privateDB.deleteRecord(
                withID: CKRecord.ID(recordName: savedName, zoneID: zone.zoneID))
        }
        // Remove the old ShareRoot metadata record that hierarchy-based sharing required.
        _ = try? await privateDB.deleteRecord(
            withID: CKRecord.ID(recordName: "shareRoot", zoneID: zone.zoneID))
        UserDefaults.standard.removeObject(forKey: kShareRecordNameKey)

        // Zone must exist before we can save the share.
        try await ensureZoneExists()

        // CKShare(recordZoneID:) requires the zone to have the .zoneWideSharing capability.
        // Zones created without this capability return CKError 12/2006 "share type
        // inconsistent with zone capabilities" — the save fails silently per-record while
        // modifyRecordsResultBlock still reports success, leaving share.url permanently nil.
        // Fix: delete and recreate the zone. Entries are safe in DataStore (UserDefaults)
        // and will re-upload automatically via CloudKitManager on the next sync.
        let allZones = try await privateDB.allRecordZones()
        if let existingZone = allZones.first(where: { $0.zoneID.zoneName == kZoneName }) {
            let hasSharing = existingZone.capabilities.contains(.zoneWideSharing)
            smLog("[SharingManager] Zone capabilities rawValue=\(existingZone.capabilities.rawValue) zoneWideSharing=\(hasSharing)")
            if !hasSharing {
                smLog("[SharingManager] Zone lacks zoneWideSharing — deleting and recreating zone")
                try await migrateZoneForZoneWideSharing()
            }
        }

        // Zone-based share: every record in MommysLogZone — past and future — is
        // automatically visible to (and writable by) participants.
        let share = CKShare(recordZoneID: zone.zoneID)
        share[CKShare.SystemFieldKey.title] = "Mommy's Log" as CKRecordValue
        share.publicPermission = .readWrite   // anyone with the link can accept

        smLog("[SharingManager] fetchOrCreateShare: saving new CKShare(recordZoneID:). localRecordID=\(share.recordID.recordName)")

        var serverShare: CKShare?
        // Track the server-assigned recordID separately from the CKShare cast.
        // If `record as? CKShare` fails (a CloudKit quirk on some iOS builds that returns
        // CKRecord instead of CKShare from perRecordSaveBlock), we still have the correct
        // server-side recordID to use for the fetch-back.
        var serverRecordID: CKRecord.ID?
        // CKShare saves can fail per-record while modifyRecordsResultBlock reports success.
        // Capture the error here so we can throw after the operation completes.
        var shareOperationError: Error?

        let op = CKModifyRecordsOperation(recordsToSave: [share])
        op.savePolicy = .ifServerRecordUnchanged
        op.perRecordSaveBlock = { recordID, result in
            smLog("[SharingManager] perRecordSaveBlock fired: recordName=\(recordID.recordName)")
            switch result {
            case .success(let record):
                serverRecordID = record.recordID
                smLog("[SharingManager]   recordType=\(record.recordType) isShare=\(record is CKShare)")
                if let ck = record as? CKShare {
                    smLog("[SharingManager]   cast to CKShare succeeded. URL=\(String(describing: ck.url))")
                    serverShare = ck
                } else {
                    smLog("[SharingManager]   cast to CKShare FAILED — will fetch back using serverRecordID=\(record.recordID.recordName)")
                }
            case .failure(let e):
                smLog("[SharingManager]   perRecordSaveBlock error: \(e)")
                shareOperationError = e
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                smLog("[SharingManager] modifyRecordsResultBlock fired")
                switch result {
                case .success:            cont.resume()
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            privateDB.add(op)
        }

        // Surface the per-record error (e.g., a zone-capabilities issue that migration missed).
        if let err = shareOperationError {
            smLog("[SharingManager] Share save failed per-record — throwing: \(err)")
            throw err
        }

        smLog("[SharingManager] After save: serverShare.url=\(String(describing: serverShare?.url)) serverRecordID=\(String(describing: serverRecordID?.recordName))")

        // Happy path: perRecordSaveBlock gave us a CKShare with a URL.
        if let ck = serverShare, ck.url != nil {
            smLog("[SharingManager] Using serverShare from perRecordSaveBlock. URL=\(ck.url!)")
            UserDefaults.standard.set(ck.recordID.recordName, forKey: kShareRecordNameKey)
            UserDefaults.standard.set(kCurrentShareVersion, forKey: kShareVersionKey)
            SyncStateManager.shared.hasPartnerShare = true
            return ck
        }

        // URL not in the save response — fetch the share back from CloudKit.
        // Use the server-assigned recordID when available (the cast may have failed,
        // but the recordID is still valid for a direct fetch).
        let fetchID = serverRecordID ?? serverShare?.recordID ?? share.recordID
        smLog("[SharingManager] URL missing in save response — fetching back. fetchID=\(fetchID.recordName)")
        do {
            let fetched = try await privateDB.record(for: fetchID)
            smLog("[SharingManager] Fetch-back: recordType=\(fetched.recordType) isShare=\(fetched is CKShare)")
            if let fetchedShare = fetched as? CKShare {
                smLog("[SharingManager] Fetch-back URL=\(String(describing: fetchedShare.url))")
                let idToSave = fetchedShare.recordID.recordName
                UserDefaults.standard.set(idToSave, forKey: kShareRecordNameKey)
                UserDefaults.standard.set(kCurrentShareVersion, forKey: kShareVersionKey)
                SyncStateManager.shared.hasPartnerShare = true
                return fetchedShare
            } else {
                smLog("[SharingManager] Fetch-back cast to CKShare FAILED")
            }
        } catch {
            smLog("[SharingManager] Fetch-back error: \(error)")
        }

        // Last resort: the share IS saved on the server (operation succeeded), but we
        // couldn't capture the URL. Return what we have — getShareURL() will retry.
        let finalShare = serverShare ?? share
        let finalName  = serverRecordID?.recordName ?? finalShare.recordID.recordName
        smLog("[SharingManager] Last resort: returning share with URL=\(String(describing: finalShare.url))")
        UserDefaults.standard.set(finalName, forKey: kShareRecordNameKey)
        UserDefaults.standard.set(kCurrentShareVersion, forKey: kShareVersionKey)
        SyncStateManager.shared.hasPartnerShare = true
        return finalShare
    }

    // Saves a modified CKShare back to iCloud (e.g. after correcting publicPermission).
    private func saveUpdatedShare(_ share: CKShare) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: [share])
            op.savePolicy = .changedKeys
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let error): cont.resume(throwing: error)
                }
            }
            self.privateDB.add(op)
        }
    }
}

// ─── UICloudSharingControllerDelegate ─────────────────────────────────────────
// 📖 SWIFT CONCEPT: Delegate
// A delegate is an object that handles events for another object.
// UICloudSharingController fires these callbacks when the user interacts
// with the share sheet. We respond here to update our state.

private class ShareDelegate: NSObject, UICloudSharingControllerDelegate {

    static let shared = ShareDelegate()

    func cloudSharingController(_ csc: UICloudSharingController,
                                failedToSaveShareWithError error: Error) {
        Task { @MainActor in
            SharingManager.shared.errorMessage = "Share save failed: \(error.localizedDescription)"
        }
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        Task { @MainActor in
            SyncStateManager.shared.isPartnerConnected = true
        }
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        Task { @MainActor in
            SyncStateManager.shared.isPartnerConnected = false
            SyncStateManager.shared.hasPartnerShare = false
        }
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        return "Mommy's Log"
    }

    func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
        return nil
    }
}
