//
//  EntryChangeLedger.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// THE EXPLICIT-EVENT SOURCE of the CKSyncEngine architecture
// (SYNC_AUDIT.md §8).
//
// The old engine INFERRED changes by diffing the live entries array against
// server-state ledgers (uploadedIDs) guarded by timing flags — any missed
// window silently diverged the two phones forever. This actor replaces all
// of that with one persisted "shadow" of the last-observed LOCAL state:
//
//     [entry UUID → {fingerprint, modifiedAt, cached CKRecord system fields}]
//
// diff(current) compares the live entries against the shadow and returns
// EXACT events: creates (id not in shadow), edits (fingerprint differs),
// deletes (id gone from current). The shadow is persisted BEFORE the diff
// returns, so a crash between "diff" and "enqueue to engine" is recovered by
// SyncCoordinator's reconcile-on-start (it re-diffs; already-recorded rows
// produce no phantom events).
//
// INVARIANT (the one rule that kills the echo problem): inbound changes from
// CloudKit are recorded here via recordInbound(...) BEFORE DataStore is
// mutated. The next diff then sees shadow == store for those ids → no event,
// no re-upload loop, no isApplyingInboundSync gating, no timing windows.
//
// Being an ACTOR serializes every read-modify-write — concurrent triggers
// (observer, foreground, push) can never interleave mid-diff.
// ─────────────────────────────────────────────────────────────

import CloudKit
import Foundation

struct EntryChangeSet: Sendable {
    var saves: [UUID] = []     // creates + edits
    var deletes: [UUID] = []
    var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }
}

actor EntryChangeLedger {

    struct Row: Codable {
        var fingerprint: String
        var modifiedAt: Date
        // Archived record.encodeSystemFields() — carries the server recordChangeTag
        // so re-saves pass CKSyncEngine's .ifServerRecordUnchanged policy. nil for
        // rows that predate the engine or haven't round-tripped yet; their first
        // edit takes one self-healing serverRecordChanged round-trip.
        var systemFields: Data?
    }

    private var rows: [UUID: Row] = [:]
    private let fileURL: URL
    private(set) var isSeeded: Bool

    // MARK: - Init / persistence

    init(filename: String = "mommyslog.sync.ledger.json") {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([UUID: Row].self, from: data) {
            rows = decoded
            isSeeded = true
        } else {
            isSeeded = false
        }
    }

    private func persist() {
        // Atomic write — a crash mid-write can never corrupt the ledger.
        if let data = try? JSONEncoder().encode(rows) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Migration seed

    /// One-time migration: adopt the current local entries as the baseline WITHOUT
    /// emitting any change events — so updating the app never mass re-uploads.
    /// modifiedAt = entry.timestamp (deterministic on BOTH phones, so seeding can
    /// never manufacture a conflict between them).
    func seed(from entries: [EntryWrapper]) {
        guard !isSeeded else { return }
        rows = [:]
        for entry in entries {
            rows[entry.id] = Row(fingerprint: EntryRecordCoding.fingerprint(entry),
                                 modifiedAt: entry.timestamp,
                                 systemFields: nil)
        }
        isSeeded = true
        persist()
    }

    // MARK: - Outbound: diff local state against the shadow

    /// Returns the EXACT set of local changes since the last observation and
    /// advances the shadow to match `current`. Call with a FRESH read of
    /// DataStore.entries (the caller reads it at execution time, not capture time).
    func diff(against current: [EntryWrapper]) -> EntryChangeSet {
        var changes = EntryChangeSet()
        var currentIDs = Set<UUID>()
        currentIDs.reserveCapacity(current.count)

        for entry in current {
            // Duplicated UUIDs in the array collapse naturally (dict-keyed shadow;
            // first occurrence wins, matching DataStore.removeDuplicates()).
            guard currentIDs.insert(entry.id).inserted else { continue }
            let fp = EntryRecordCoding.fingerprint(entry)
            if let row = rows[entry.id] {
                if row.fingerprint != fp {
                    // EDIT — same id, different content. Stamp NOW for last-writer-wins.
                    rows[entry.id] = Row(fingerprint: fp, modifiedAt: Date(),
                                         systemFields: row.systemFields)
                    changes.saves.append(entry.id)
                }
            } else {
                // CREATE
                rows[entry.id] = Row(fingerprint: fp, modifiedAt: Date(), systemFields: nil)
                changes.saves.append(entry.id)
            }
        }

        // DELETES — ids the shadow knows that are gone from the store.
        let deleted = rows.keys.filter { !currentIDs.contains($0) }
        for id in deleted {
            rows.removeValue(forKey: id)
            changes.deletes.append(id)
        }

        if !changes.isEmpty { persist() }
        return changes
    }

    // MARK: - Inbound: record server truth BEFORE mutating DataStore

    /// Record inbound upserts/deletes so the next diff sees no phantom local change.
    /// MUST be awaited before DataStore.applyInboundUpserts/Deletes runs.
    func recordInbound(upserts: [(entry: EntryWrapper, record: CKRecord)], deletes: [UUID]) {
        for (entry, record) in upserts {
            rows[entry.id] = Row(fingerprint: EntryRecordCoding.fingerprint(entry),
                                 modifiedAt: EntryRecordCoding.modifiedAt(of: record),
                                 systemFields: encodeSystemFields(of: record))
        }
        for id in deletes {
            rows.removeValue(forKey: id)
        }
        if !upserts.isEmpty || !deletes.isEmpty { persist() }
    }

    /// After the engine confirms a save (sentRecordZoneChanges.savedRecords):
    /// cache the server's system fields + authoritative modifiedAt.
    func recordSaved(_ record: CKRecord) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        var row = rows[id] ?? Row(fingerprint: "", modifiedAt: .distantPast, systemFields: nil)
        row.systemFields = encodeSystemFields(of: record)
        row.modifiedAt = EntryRecordCoding.modifiedAt(of: record)
        rows[id] = row
        persist()
    }

    /// A save failed with .unknownItem (record vanished server-side) — drop the
    /// stale system fields so the retry creates a fresh record.
    func clearSystemFields(for id: UUID) {
        guard rows[id] != nil else { return }
        rows[id]?.systemFields = nil
        persist()
    }

    // MARK: - Reads

    func systemFields(for id: UUID) -> Data? { rows[id]?.systemFields }
    func modifiedAt(for id: UUID) -> Date?   { rows[id]?.modifiedAt }
    func fingerprint(for id: UUID) -> String? { rows[id]?.fingerprint }
    func allIDs() -> Set<UUID>               { Set(rows.keys) }
    func count() -> Int                      { rows.count }

    // MARK: - Reset (leave share / revoke / sign-out)

    func reset() {
        rows = [:]
        isSeeded = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    private func encodeSystemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }
}
