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
ContentView (TabView — 5 tabs)
├── FeedingView — log breast/bottle/formula
├── DiaperView — log wet/poop/mixed
├── TodayView — daily stats + recent activity
├── HistoryView — full history, swipe to edit/delete
└── SettingsView — reminders, export, data management

DataStore (@StateObject in ContentView, @EnvironmentObject everywhere else)
└── Persists to UserDefaults + Document backup JSON
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
