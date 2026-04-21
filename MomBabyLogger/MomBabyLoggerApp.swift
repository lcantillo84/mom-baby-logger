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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                .onAppear {
                    // Wire CloudKit sync as soon as the app is on screen.
                    // configure() is a no-op if the user is not Pro.
                    CloudKitManager.shared.configure(with: dataStore)
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

