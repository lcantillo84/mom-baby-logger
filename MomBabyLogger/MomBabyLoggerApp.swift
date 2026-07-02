//
//  MomBabyLoggerApp.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI
import UserNotifications

@main
struct MomBabyLoggerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    // The single DataStore for the whole app. @StateObject means SwiftUI owns it.
    @StateObject private var dataStore = DataStore()

    init() {
        AnalyticsManager.shared.trackAppOpen()
        configureAppearance()
    }

    private func configureAppearance() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(AppTheme.Colors.cardBackground)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

        // Fix white navigation bar headers on all iPhones — without this,
        // iOS renders the scrollEdge appearance as transparent/white on some devices.
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(AppTheme.Colors.appBackground)
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(AppTheme.Colors.primaryText)
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(AppTheme.Colors.primaryText)
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(AppTheme.Colors.primaryAction)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                // The app uses a fixed light "spa cream/teal" palette (all AppTheme colors are
                // hardcoded light values). It was never designed for dark mode, so on a dark-mode
                // device system containers + default text flip to white and become unreadable.
                // Lock the whole scene (including sheets) to light so the brand palette always shows.
                .preferredColorScheme(.light)
                .onAppear {
                    // Clean any duplicate entries (same id) left by earlier concurrent syncs
                    // BEFORE sync starts, so uploads aren't poisoned and History shows no doubles.
                    let removed = dataStore.removeDuplicates()
                    if removed > 0 { print("[DataStore] removeDuplicates: cleaned \(removed) duplicate entr(ies)") }

                    // One-time: clear the stale "Partner" badges that were mis-applied to the
                    // owner's OWN logs during earlier Force Re-upload/Refetch (which wiped the
                    // "who logged what" list). Tags rebuild correctly for new partner entries.
                    if !UserDefaults.standard.bool(forKey: "mommyslog.partnerTagsResetV1") {
                        UserDefaults.standard.removeObject(forKey: "mommyslog.partnerEntryIDs")
                        UserDefaults.standard.set(true, forKey: "mommyslog.partnerTagsResetV1")
                    }
                    CloudKitManager.shared.configure(with: dataStore)
                    WidgetSnapshotWriter.shared.start(observing: dataStore)
                    SubscriptionManager.shared.startTransactionListener()
                    Task { await SubscriptionManager.shared.checkCurrentEntitlements() }
                    // Self-heal share/connection state from CloudKit ground truth on every
                    // launch. Keeps both phones in agreement with no user action.
                    Task { await SharingManager.shared.reconcileState() }
                    #if DEBUG
                    // Xcode debug builds use StoreKit sandbox, which can't see App Store
                    // production subscriptions. Auto-activate Pro so all features are
                    // testable without going through StoreKit. Strips from App Store builds.
                    // Use "Force Reset State" in Partner Sync debug panel to test free flow.
                    SyncStateManager.shared.activatePro()
                    #endif
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // On foreground: first re-derive the true connection state, then pull any
                    // new entries. Reconciling first means a share that was joined/left/revoked
                    // on the other phone is reflected here automatically — no manual repair.
                    if newPhase == .active {
                        Task {
                            await SharingManager.shared.reconcileState()
                            // Push pending local logs UP first (covers entries logged just
                            // before backgrounding), then pull the partner's changes DOWN.
                            // fetchOnForeground does a full re-fetch for participants so the
                            // owner's edits (which the delta feed misses) come through.
                            await CloudKitManager.shared.pushPendingChanges()
                            await CloudKitManager.shared.fetchOnForeground()
                        }
                    }
                }
        }
    }
}
// App Delegate for handling notification callbacks
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Register for silent CloudKit push notifications (needed for background sync).
        registerForRemoteNotifications()
        return true
    }
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // User tapped on the notification
        // Could navigate to feeding view here if needed
        completionHandler()
    }
}

