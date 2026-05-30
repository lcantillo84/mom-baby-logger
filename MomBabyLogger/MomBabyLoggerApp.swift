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
                .onAppear {
                    CloudKitManager.shared.configure(with: dataStore)
                    SubscriptionManager.shared.startTransactionListener()
                    Task { await SubscriptionManager.shared.checkCurrentEntitlements() }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Pull any new entries whenever the user brings the app to the foreground.
                    // Silent push notifications are unreliable — this ensures Phone 2 always
                    // sees up-to-date data without having to open PartnerSyncView manually.
                    if newPhase == .active {
                        Task { await CloudKitManager.shared.fetchChanges() }
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

