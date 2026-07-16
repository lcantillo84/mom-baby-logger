//
//  AppDelegate+CloudKit.swift
//  MomBabyLogger
//

import CloudKit
import UIKit

extension AppDelegate {

    // ─── Register for Silent Push Notifications ───────────────────────────
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {}

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[CloudKit] Push registration failed: \(error.localizedDescription)")
    }

    // ─── Handle Incoming Silent Push ─────────────────────────────────────
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            // v2 engine: hand the push to the SyncCoordinator (via the facade),
            // which nudges CKSyncEngine to fetch. Engine-managed pushes replaced
            // the old manual zone/database subscriptions.
            let consumed = CloudKitManager.shared.handleRemoteNotification(userInfo)
            completionHandler(consumed ? .newData : .noData)
        }
    }

    // ─── Wire Up SceneDelegate for CloudKit Share Acceptance ─────────────
    // iOS 13+ delivers the share-acceptance callback to UIWindowSceneDelegate,
    // not UIApplicationDelegate. We register MomSceneDelegate here so the
    // callback is guaranteed to arrive regardless of iOS version.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = MomSceneDelegate.self
        return config
    }

    // AppDelegate fallback — fires on older iOS or if scene delegate misses it.
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            await SharingManager.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }
}

// ─── MomSceneDelegate ─────────────────────────────────────────────────────────
// Handles the scene-level CloudKit share acceptance (iOS 13+).
// Does NOT implement scene(_:willConnectTo:options:) — SwiftUI manages the
// window setup; we only add the CloudKit callback here.
class MomSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            await SharingManager.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }
}
