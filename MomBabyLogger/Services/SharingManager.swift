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

    private lazy var zone: CKRecordZone = {
        CKRecordZone(zoneName: kZoneName)
    }()

    // UserDefaults key to remember the share's record name between launches.
    private let kShareRecordNameKey = "mommyslog.shareRecordName"

    private init() {}

    // ─── Load Existing Share ───────────────────────────────────────────────

    // Call this when PartnerSyncView appears to show current share status.
    func loadExistingShare() async {
        isLoading = true
        defer { isLoading = false }

        // If we saved a record name before, try to fetch that exact share.
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
        SyncStateManager.shared.deactivatePro()
        UserDefaults.standard.removeObject(forKey: kShareRecordNameKey)
        activeShare = nil
    }

    // ─── Accept Incoming Share (Partner Side) ─────────────────────────────

    // Called from AppDelegate+CloudKit when the partner taps the link.
    // Accepts the CloudKit share, then fetches all mom's existing entries.
    func acceptShare(metadata: CKShare.Metadata) async {
        do {
            // 📖 SWIFT CONCEPT: CKAcceptSharesOperation
            // This is the handshake — partner's device tells Apple "yes, I accept."
            // After this, the shared zone appears in partner's sharedCloudDatabase.
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

            SyncStateManager.shared.isPartnerConnected = true
            SyncStateManager.shared.hasPartnerShare = true
            SyncStateManager.shared.isParticipant = true   // this device accepted, not created
            SyncStateManager.shared.activatePro()          // participants get sync for free

            // If the app was already running, boot() ran earlier with isParticipant=false
            // and set up owner-mode subscriptions. Re-run boot() now so Phone 2 gets
            // the shared DB subscription and Combine observer wired correctly.
            CloudKitManager.shared.startSyncAfterJoining()

            // Reset shared zone tokens so the first fetch returns ALL of Phone 1's records,
            // not just incremental changes since a (possibly stale) previous token.
            CloudKitManager.shared.clearSharedZoneTokens()
            await CloudKitManager.shared.fetchChanges()

        } catch {
            errorMessage = "Could not accept share: \(error.localizedDescription)"
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

    private func fetchOrCreateShare() async throws -> CKShare {
        // Reuse existing share if we have one — but ensure permission is correct.
        // publicPermission must be .readWrite so anyone with the URL can accept.
        // Old shares may have been saved with the default .none, which causes
        // "Item Unavailable" when the recipient taps the link.
        if let existing = activeShare {
            if existing.publicPermission != .readWrite {
                existing.publicPermission = .readWrite
                try? await saveUpdatedShare(existing)
            }
            return existing
        }

        // Zone must exist before we can save any records (including a CKShare).
        // CloudKit returns notAuthenticated — confusingly — when the zone is missing.
        try await ensureZoneExists()

        // CKShare needs to be associated with a "root record."
        // We use a dedicated metadata record (not an entry) as the share root.
        let rootRecordID = CKRecord.ID(recordName: "shareRoot", zoneID: zone.zoneID)

        do {
            // Try fetching an existing root record + its share.
            let rootRecord = try await privateDB.record(for: rootRecordID)
            // If the root record exists, try to find its associated share.
            if let shareRef = rootRecord.share,
               let shareRecord = try? await privateDB.record(for: shareRef.recordID),
               let share = shareRecord as? CKShare {
                // Fix permission on any existing share that was saved with .none.
                if share.publicPermission != .readWrite {
                    share.publicPermission = .readWrite
                    try? await saveUpdatedShare(share)
                }
                UserDefaults.standard.set(share.recordID.recordName, forKey: kShareRecordNameKey)
                return share
            }
        } catch { /* root record doesn't exist yet — create it below */ }

        // First time: create the root record and its CKShare together.
        let rootRecord = CKRecord(recordType: "ShareRoot", recordID: rootRecordID)
        rootRecord["app"] = "MommysLog" as CKRecordValue

        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Mommy's Log" as CKRecordValue
        // Allow anyone with the link to accept the share (required for UIActivityViewController flow).
        share.publicPermission = .readWrite

        // Save both the root record and the share in one atomic operation.
        let op = CKModifyRecordsOperation(recordsToSave: [rootRecord, share])
        op.savePolicy = .ifServerRecordUnchanged

        // Capture the server-returned share so we get the URL Apple assigns after save.
        var serverShare: CKShare?
        op.perRecordSaveBlock = { _, result in
            if case .success(let record) = result, let ckShare = record as? CKShare {
                serverShare = ckShare
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            privateDB.add(op)
        }

        let finalShare = serverShare ?? share
        UserDefaults.standard.set(finalShare.recordID.recordName, forKey: kShareRecordNameKey)
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
