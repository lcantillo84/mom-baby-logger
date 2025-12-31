//
//  NotificationManager.swift
//  MomBabyLogger
//
//  Manager for feeding reminder notifications
//

import Foundation
import UserNotifications
import Combine
import UIKit

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let reminderIdentifier = "feedingReminder"
    
    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    // MARK: - Authorization
    
    /// Request notification permission from the user
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            return granted
        } catch {
            print("Error requesting notification authorization: \(error)")
            return false
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    // MARK: - Reminder Scheduling
    
    /// Schedule a reminder notification based on settings and last feeding time
    /// - Parameters:
    ///   - lastFeedingTime: The timestamp of the most recent feeding (any type)
    ///   - settings: The current reminder settings
    func scheduleReminder(for lastFeedingTime: Date, settings: ReminderSettings) async {
        // Cancel any existing reminders first
        await cancelReminder()
        
        // Don't schedule if reminders are disabled
        guard settings.isEnabled else {
            return
        }
        
        // Check authorization status
        await checkAuthorizationStatus()
        guard authorizationStatus == .authorized else {
            print("Notifications not authorized, cannot schedule reminder")
            return
        }
        
        // Calculate when the reminder should fire
        let reminderTime = lastFeedingTime.addingTimeInterval(settings.intervalSeconds)
        
        // Don't schedule if the reminder time is in the past
        guard reminderTime > Date() else {
            print("Reminder time is in the past, not scheduling")
            return
        }
        
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Feeding Reminder"
        content.body = "It's been \(settings.intervalDisplayText) since the last feeding"
        content.sound = .default
        content.categoryIdentifier = "FEEDING_REMINDER"
        
        // Calculate time interval from now
        let timeInterval = reminderTime.timeIntervalSinceNow
        
        // Create trigger
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        
        // Create request
        let request = UNNotificationRequest(
            identifier: reminderIdentifier,
            content: content,
            trigger: trigger
        )
        
        // Schedule notification
        do {
            try await notificationCenter.add(request)
            print("Scheduled feeding reminder for \(reminderTime)")
        } catch {
            print("Error scheduling notification: \(error)")
        }
    }
    
    /// Cancel any pending reminder notifications
    func cancelReminder() async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        print("Cancelled pending feeding reminders")
    }
    
    /// Get information about the next scheduled reminder
    /// - Returns: The date of the next reminder, or nil if none is scheduled
    func getNextReminderDate() async -> Date? {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        
        guard let reminderRequest = pendingRequests.first(where: { $0.identifier == reminderIdentifier }),
              let trigger = reminderRequest.trigger as? UNTimeIntervalNotificationTrigger else {
            return nil
        }
        
        // Calculate the absolute date from the trigger
        let nextTriggerDate = trigger.nextTriggerDate()
        return nextTriggerDate
    }
    
    // MARK: - Helper Methods
    
    /// Check if notifications are authorized
    var isAuthorized: Bool {
        return authorizationStatus == .authorized
    }
    
    /// Check if notifications can be requested (not denied or permanently disabled)
    var canRequestAuthorization: Bool {
        return authorizationStatus == .notDetermined
    }
    
    /// Open system settings for the app (for when user needs to enable notifications manually)
    func openAppSettings() {
        if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            Task { @MainActor in
                await UIApplication.shared.open(appSettings)
            }
        }
    }
}
