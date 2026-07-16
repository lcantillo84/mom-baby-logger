//
//  EntryRecordCoding.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// SINGLE SOURCE OF TRUTH for how an EntryWrapper becomes a CKRecord
// and back, and for the normalized content fingerprint.
//
// Extracted verbatim from CloudKitManager (2026-07-08) as Phase 1 of the
// CKSyncEngine re-architecture (see SYNC_AUDIT.md §8). The record shape is
// FROZEN — records with this exact shape already exist in the production
// CloudKit database, so changing any field name or the recordType breaks
// every existing user.
//
// Record shape (recordType "Entry", recordName = entry UUID string):
//   entryData      String  — the FULL EntryWrapper encoded as JSON
//   entryTimestamp Date    — the logical timestamp (for dashboard queries)
//   entryType      String  — "feeding" / "diaper"
//   schemaVersion  Int     — 1
//   modifiedAt     Date    — NEW (v2 engine): last-writer-wins conflict stamp,
//                            set when the local change event was captured.
//                            ⚠️ Must be deployed to the PRODUCTION CloudKit
//                            schema before any v2 build ships (CloudKit Console
//                            → Schema → Deploy Schema Changes to Production).
// ─────────────────────────────────────────────────────────────

import CloudKit
import Foundation

enum EntryRecordCoding {

    static let recordType = "Entry"

    // ─── CKRecord ← EntryWrapper ───────────────────────────────────────────

    static func makeRecordID(for id: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        // recordName = the entry's UUID. CloudKit uses this as the primary key.
        // Two devices saving the same UUID = only one record (natural dedup).
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    // Writes an entry's fields onto a CKRecord. Used both when CREATING a fresh
    // record and when MODIFYING an existing server record (which carries its
    // recordChangeTag) — one place defines the record shape.
    // Returns false if the entry can't be encoded.
    @discardableResult
    static func applyEntryFields(_ entry: EntryWrapper, modifiedAt: Date, to record: CKRecord) -> Bool {
        guard let jsonData = try? JSONEncoder().encode(entry),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return false
        }
        record["entryData"]      = jsonString as CKRecordValue
        record["entryTimestamp"] = entry.timestamp as CKRecordValue
        record["schemaVersion"]  = 1 as CKRecordValue
        record["modifiedAt"]     = modifiedAt as CKRecordValue
        switch entry {
        case .feeding: record["entryType"] = "feeding" as CKRecordValue
        case .diaper:  record["entryType"] = "diaper"  as CKRecordValue
        }
        return true
    }

    // ─── EntryWrapper ← CKRecord ───────────────────────────────────────────

    static func makeEntry(from record: CKRecord) -> EntryWrapper? {
        guard let jsonString = record["entryData"] as? String,
              let jsonData   = jsonString.data(using: .utf8),
              let entry      = try? JSONDecoder().decode(EntryWrapper.self, from: jsonData) else {
            return nil
        }
        return entry
    }

    // The record's last-writer-wins stamp. Records written before the v2 engine
    // lack the modifiedAt field — fall back to CloudKit's own modificationDate
    // so conflicts against legacy records still resolve deterministically.
    static func modifiedAt(of record: CKRecord) -> Date {
        (record["modifiedAt"] as? Date) ?? record.modificationDate ?? .distantPast
    }

    // ─── Normalized Content Fingerprint ────────────────────────────────────
    //
    // ⚠️ FORMAT IS FROZEN — NEVER CHANGE IT (see SYNC_AUDIT.md RC-E).
    // Stable, NORMALIZED fingerprint of an entry's MEANINGFUL content. Timestamps
    // are rounded to whole seconds and doubles formatted to fixed decimals, so the
    // JSON round-trip through CloudKit (which can shift sub-second Date precision)
    // can NEVER produce a different fingerprint for the same logical entry.
    // Hashing raw JSON did exactly that and caused a perpetual "everything edited"
    // re-upload storm. Do NOT go back to hashing raw bytes.
    static func fingerprint(_ entry: EntryWrapper) -> String {
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
}
