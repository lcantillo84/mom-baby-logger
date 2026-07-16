//
//  DataStore+SyncEngine.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// Inbound-sync application for the CKSyncEngine architecture
// (SYNC_AUDIT.md §8). DataStore.swift itself is OFF-LIMITS and is
// NOT modified — this is a purely ADDITIVE extension in its own file
// (same pattern as removeDuplicates(), which was the previously
// approved additive change).
//
// WHY THIS EXISTS: the legacy engine could only ADD inbound entries
// (applyInboundEntries filters to new ids), so inbound EDITS had to be
// applied as delete-then-re-add — which required fragile timing flags to
// stop the observer from treating the transient deletion as a real one.
// Upsert-in-place removes that entire failure class.
//
// SIDE-EFFECT POLICY: inbound applies never fire analytics, review
// prompts, or feeding reminders — those belong to the LOCAL user's own
// actions only (matches applyInboundEntries' behavior).
// ─────────────────────────────────────────────────────────────

import Foundation

extension DataStore {

    /// Insert-or-replace entries by id, then re-sort and persist.
    /// - New ids are appended; existing ids are replaced IN PLACE (same-UUID edit),
    ///   which is how EditEntryView edits look when they arrive from the other phone.
    /// - Sets `isApplyingInboundSync` for parity with the legacy engine; the v2
    ///   engine's correctness does NOT depend on it (the change ledger is updated
    ///   before this runs, so the next diff sees no phantom local change).
    func applyInboundUpserts(_ upserts: [EntryWrapper]) {
        guard !upserts.isEmpty else { return }
        isApplyingInboundSync = true
        defer { isApplyingInboundSync = false }

        var indexByID: [UUID: Int] = [:]
        for (i, entry) in entries.enumerated() { indexByID[entry.id] = i }

        for entry in upserts {
            if let i = indexByID[entry.id] {
                entries[i] = entry
            } else {
                indexByID[entry.id] = entries.count
                entries.append(entry)
            }
        }
        entries.sort { $0.timestamp > $1.timestamp }
        persistAfterInboundChange()
        recalcBreastSideAfterInbound()
    }

    /// Remove entries whose ids were deleted on the other device.
    func applyInboundDeletes(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        isApplyingInboundSync = true
        defer { isApplyingInboundSync = false }

        let before = entries.count
        entries.removeAll { ids.contains($0.id) }
        guard entries.count != before else { return }
        persistAfterInboundChange()
        recalcBreastSideAfterInbound()
    }

    // ─── Private mirrors of DataStore's persistence ────────────────────────
    // saveData()/recalculateLastBreastSide() are `private` in DataStore.swift
    // (L202 / L237), so this extension mirrors them against the same stable,
    // documented storage: UserDefaults key "BabyTrackerEntries" + the backup
    // JSON file "baby_tracker_backup.json" in Documents. If DataStore's
    // persistence ever changes (it shouldn't — the file is frozen), update here.

    private func persistAfterInboundChange() {
        if let encoded = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(encoded, forKey: "BabyTrackerEntries")
            let backupURL = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("baby_tracker_backup.json")
            try? encoded.write(to: backupURL)
        }
    }

    private func recalcBreastSideAfterInbound() {
        // Mirror of DataStore.recalculateLastBreastSide(): suggest the opposite
        // side of the most recent breast feeding; default .left with no history.
        let breastFeedings = entries.compactMap { entry -> (side: BreastSide, timestamp: Date)? in
            if case .feeding(let f) = entry, f.type == .breastFeeding, let side = f.side {
                return (side: side, timestamp: f.timestamp)
            }
            return nil
        }
        if let mostRecent = breastFeedings.max(by: { $0.timestamp < $1.timestamp }) {
            lastBreastSide = mostRecent.side == .left ? .right : .left
        } else {
            lastBreastSide = .left
        }
    }
}
