# Mommy's Log — Development Guide

## App Overview
Published iOS baby tracker app (App Store: "Mommy's Log"). Tracks feedings (breast/bottle/formula) and diaper changes. Target user: sleep-deprived moms logging baby activity at any hour. Baby can be a boy or girl — all design must be gender-neutral.

**Bundle ID:** lilycantilloapp.mommysblog  
**Deployment Target:** iOS 17.6+  
**Architecture:** SwiftUI + single ObservableObject DataStore

---

## ABSOLUTE RULES — Never Break These

### Never Touch the Data Layer
These files are off-limits for any modification:
- `Models/DataStore.swift`
- `Models/FeedingEntry.swift`
- `Models/DiaperEntry.swift`
- `Models/ActivityEntry.swift`
- `Models/DailyStats.swift`
- `Models/ReminderSettings.swift`
- `Models/NotificationManager.swift`
- `Helpers/AnalyticsManager.swift`
- `Helpers/ReviewManager.swift`
- `Helpers/AppVersionManager.swift`
- `Helpers/KeyboardHelpers.swift`

### Never Touch Logic in Views
Even in view files, these are sacred:
- Any `private func log*()` function
- Any `private func save*()` function
- Any `@EnvironmentObject var dataStore` reference
- Any `DispatchQueue.main.asyncAfter` call (timing is intentional UX)
- Any `sheet()`, `alert()`, `confirmationDialog()` modifier
- All enums: `FeedingType`, `DeleteTimeframe`, `ExportTimeframe`, `ExportFormat`
- All `@State` bindings that drive logic (not just appearance)

---

## Design System

All visual tokens live in `AppTheme.swift`. Never hardcode colors or spacing.

### Color Usage
```swift
// WRONG
.background(Color.blue)
.foregroundColor(.green)

// RIGHT
.background(AppTheme.Colors.primaryAction)
.foregroundColor(AppTheme.Colors.primaryText)
```

### Design Palette (Spa-Calm Wellness, Gender-Neutral)
- **Hero:** `AppTheme.Colors.primaryAction` = deep teal `#3D7A72` — calm, universal, spa energy
- **Background:** `AppTheme.Colors.appBackground` = warm cream `#FFF9F4`
- **Cards:** `AppTheme.Colors.cardBackground` = `#FFFCF9`
- **Activity colors:** sandRose (breast), dustySky (bottle/wet), warmSand (formula), caramel (poop), slateBlue (mixed)

### Typography
Use `AppTheme.Typography.*` instead of raw `.font(.headline)` etc.

### Spacing & Radius
Use `AppTheme.Spacing.*` and `AppTheme.Radius.*` constants.

---

## Architecture

```
ContentView (TabView — 6 tabs)
├── FeedingView — log breast/bottle/formula
├── DiaperView — log wet/poop/mixed
├── TodayView — daily stats + recent activity  [person.2 button → Partner Sync]
├── HistoryView — full history, swipe to edit/delete
├── InsightsView — weekly charts (Pro)
└── SettingsView — reminders, export, data management

All main tabs have a person.2 icon (top-right nav bar) → Partner Sync / ProGate.

DataStore (@StateObject in ContentView, @EnvironmentObject everywhere else)
└── Persists to UserDefaults + Document backup JSON

Pro / Partner Sync state lives in SyncStateManager.shared (@AppStorage keys).
```

---

## Build & Test

```bash
# Build
xcodebuild -scheme MomBabyLogger -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run on simulator
open -a Simulator
xcodebuild -scheme MomBabyLogger -destination 'platform=iOS Simulator,name=iPhone 16' run
```

## Adding New Features
1. Only add to existing views or create new view files — never modify models
2. New UI components go in `Views/Components/`
3. Use `AppTheme.*` for all visual tokens
4. Test on both iPhone (portrait) and iPad (landscape)
5. Never add third-party dependencies without discussion

---

## Partner Sync — Architecture & Debug Reference

**Milestone achieved:** Zone-based CloudKit sharing (v1.5+). Both parents share a single `MommysLogZone`; all entries sync both ways automatically.

### Key files
| File | Role |
|---|---|
| `Services/SharingManager.swift` | Owns share creation, invite URL, accept flow, leave/revoke |
| `Services/SyncStateManager.swift` | Published state: `isPro`, `isParticipant`, `isPartnerConnected`, `hasAcceptedShare` |
| `Services/CloudKitManager.swift` | **OFF-LIMITS** — handles zone fetch, subscription, entry upload |
| `AppDelegate+CloudKit.swift` | **OFF-LIMITS** — routes share-acceptance URL from iOS to `SharingManager.acceptShare()` |
| `Views/Pro/PartnerSyncView.swift` | Sync control panel; includes `#if DEBUG` state inspector |

### How the share works
- **Share type:** `CKShare(recordZoneID:)` — zone-based, shares ALL records in `MommysLogZone` automatically
- **Zone requirement:** Zone must have `.zoneWideSharing` capability (auto-assigned on iOS 15+). If missing, `migrateZoneForZoneWideSharing()` deletes + recreates the zone; entries are safe in DataStore (UserDefaults) and re-upload automatically
- **Permission:** `publicPermission = .readWrite` — partner can both view and log entries
- **Invite URL:** CloudKit generates the URL server-side; it survives app relaunches via `UserDefaults` key `mommyslog.shareRecordName`

### Stop sharing — what happens
- **Owner (Phone 1) disconnects** → `revokeShare()` deletes the CKShare from iCloud → CloudKit push arrives on Phone 2 → `fetchSharedChanges()` sees empty zones → auto-revokes Phone 2's access + deactivates Pro
- **Partner (Phone 2) leaves** → `leaveShare()` clears local state only → Phone 1's share stays active → Phone 1 can re-invite any time

### Critical bug that was fixed (race condition)
`CloudKitManager.fetchSharedChanges()` resets `isParticipant=false` + calls `deactivatePro()` when `sharedDB.allRecordZones()` returns empty (e.g. zone propagation takes 5–45s on Mac Catalyst). Fix: `hasAcceptedShare` is a raw `UserDefaults` key (NOT `@AppStorage`) that CloudKitManager never touches. `SharingManager.restoreParticipantStateIfNeeded()` re-applies participant state on every Partner Sync screen open.

### Debug logging
All `[SharingManager]` prints go through `smLog()` — a `#if DEBUG`-gated helper. They compile **out** in App Store Release builds but stay in the source. To temporarily enable in Release, change `#if DEBUG` to `if true` in the `smLog()` function.

Key log markers to watch:
```
[SharingManager] restoreParticipantStateIfNeeded: hasAcceptedShare=...   ← fires every Partner Sync open
[SharingManager] acceptShareByURL: fetching metadata for ...              ← Join flow started
[SharingManager] acceptShare: called — containerID=...                    ← URL routing fired (iOS)
[SharingManager] acceptShare: CKAcceptSharesOperation succeeded           ← share accepted
[SharingManager] restoreParticipantStateIfNeeded: sharedDB zones=N        ← N>0 = zone ready, sync will start
```

### Debug panel (in-app)
`PartnerSyncView` has a `#if DEBUG` section at the bottom showing live values of all 6 state keys and a "Force Reset State" button for clean test runs. Strips from App Store builds automatically.
