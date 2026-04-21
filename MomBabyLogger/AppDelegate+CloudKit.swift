//
//  AppDelegate+CloudKit.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// This file adds two things to the app's "lifecycle brain" (AppDelegate):
//
// 1. Remote notification registration:
//    When the app starts, we tell iOS "we want to receive silent pushes."
//    Apple sends silent pushes when something changes in our iCloud zone.
//    Without registering, iOS would block those pushes.
//
// 2. Share acceptance handler:
//    When the partner taps the invite link, iOS opens our app and calls
//    `userDidAcceptCloudKitShareWith`. We hand that off to SharingManager
//    which does the CloudKit handshake and downloads mom's entries.
//
// 📖 SWIFT CONCEPT: Extension
// `extension AppDelegate` adds new methods to AppDelegate WITHOUT modifying
// the original file. It's like a sticky note on a book — adds new info
// without rewriting the book.
// ─────────────────────────────────────────────────────────────

import CloudKit
import UIKit

// 📖 SWIFT CONCEPT: @UIApplicationMain / AppDelegate
// AppDelegate is the "front door" of an iOS app. iOS calls specific methods
// on it at key moments: app opened, push received, URL opened, etc.
// We extend it here to handle CloudKit-specific events.
extension AppDelegate {

    // ─── Step 1: Register for Remote Notifications ────────────────────────

    // Call this from `application(_:didFinishLaunchingWithOptions:)` in AppDelegate.
    // It asks iOS "please send me silent pushes" — needed for background sync.
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    // iOS calls this when registration SUCCEEDS.
    // We don't need the deviceToken ourselves — CloudKit handles it internally.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // CloudKit registers automatically via the container; nothing to do here.
    }

    // iOS calls this when registration FAILS (e.g. simulator, no Apple ID signed in).
    // We log it silently — the app works fine offline, sync just won't work.
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Silent fail — sync is a Pro feature, offline mode always works.
        print("[CloudKit] Remote notification registration failed: \(error.localizedDescription)")
    }

    // ─── Step 2: Handle Incoming Silent Push ──────────────────────────────

    // 📖 SWIFT CONCEPT: Background App Refresh
    // iOS can wake your app briefly when a silent push arrives, even if the
    // user hasn't opened it. This method runs, fetches changes from iCloud,
    // and calls completionHandler to tell iOS "done, you can sleep me again."
    // Apple requires you call completionHandler quickly (within ~30 seconds).
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {

        // 📖 SWIFT CONCEPT: Task
        // `Task { }` launches an async function from a non-async context.
        // It runs concurrently without blocking the current thread.
        Task { @MainActor in
            await CloudKitManager.shared.fetchChanges()
            completionHandler(.newData)
        }
    }

    // ─── Step 3: Partner Accepts the Invite Link ──────────────────────────

    // 📖 SWIFT CONCEPT: UIScene-based lifecycle
    // Modern iOS apps use scenes (since iOS 13). When the partner taps the
    // CloudKit share link, the scene delegate gets this callback BEFORE
    // AppDelegate. We implement it in AppDelegate as a fallback for any
    // edge cases where the scene-level handler is not called.
    //
    // The main implementation lives in the scene delegate (handled in
    // `scene(_:continue:)` in the SwiftUI lifecycle through the App struct).

    // This is the UIApplicationDelegate version — fires when scene-based
    // handling is not available.
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            await SharingManager.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }
}
