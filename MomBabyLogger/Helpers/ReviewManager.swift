//
//  ReviewManager.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/15/25.
//

import Foundation
import StoreKit
import UIKit

/// Manages when to request App Store reviews from users
class ReviewManager {

    /// Shared singleton instance
    static let shared = ReviewManager()

    private let reviewRequestKey = "ReviewRequestCount"
    private let lastReviewRequestKey = "LastReviewRequestDate"
    private let firstLaunchKey = "FirstLaunchDate"

    private init() {
        // Record first launch date if not already set
        if UserDefaults.standard.object(forKey: firstLaunchKey) == nil {
            UserDefaults.standard.set(Date(), forKey: firstLaunchKey)
        }
    }

    /// Request review if appropriate conditions are met
    /// Call this after user completes meaningful actions (logging entries)
    func requestReviewIfAppropriate(entryCount: Int) {
        // Must run on main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.requestReviewIfAppropriate(entryCount: entryCount)
            }
            return
        }
        
        // Don't ask too frequently - Apple limits to 3 times per year
        guard canRequestReview() else { return }

        // Trigger conditions (any one of these)
        let shouldRequest = entryCount == 10 ||  // After 10 entries
                           entryCount == 25 ||  // After 25 entries
                           entryCount == 50 ||  // After 50 entries
                           entryCount == 100    // After 100 entries

        guard shouldRequest else { return }

        // Request review on main thread with a slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Get the active window scene
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
                print("Could not find active window scene for review request")
                return
            }
            
            // Request the review
            SKStoreReviewController.requestReview(in: scene)
            print("Review request shown at \(entryCount) entries")

            // Track that we requested
            self.incrementReviewRequestCount()
            UserDefaults.standard.set(Date(), forKey: self.lastReviewRequestKey)
        }
    }

    /// Check if we can request a review based on frequency limits
    private func canRequestReview() -> Bool {
        // Check review request count (max 3 per year)
        let requestCount = UserDefaults.standard.integer(forKey: reviewRequestKey)
        if requestCount >= 3 {
            print("Review request skipped: Already requested 3 times this year")
            return false
        }

        // Check if enough time has passed since last request (at least 2 months)
        if let lastRequest = UserDefaults.standard.object(forKey: lastReviewRequestKey) as? Date {
            let twoMonthsAgo = Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()
            if lastRequest >= twoMonthsAgo {
                print("Review request skipped: Last request was less than 2 months ago")
                return false
            }
        }

        // Check if user has been using app for at least 3 days
        if let firstLaunch = UserDefaults.standard.object(forKey: firstLaunchKey) as? Date {
            let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
            if firstLaunch >= threeDaysAgo {
                print("Review request skipped: App installed less than 3 days ago")
                return false
            }
        }

        print("Review request allowed: All conditions met")
        return true
    }

    /// Increment the review request counter
    private func incrementReviewRequestCount() {
        let currentCount = UserDefaults.standard.integer(forKey: reviewRequestKey)
        UserDefaults.standard.set(currentCount + 1, forKey: reviewRequestKey)
        print("Review request count incremented to \(currentCount + 1)")
    }

    /// Reset review request count (call this at the start of a new year)
    func resetYearlyCount() {
        UserDefaults.standard.set(0, forKey: reviewRequestKey)
        print("Review request count reset to 0")
    }
    
    // MARK: - Debug Helpers
    
    /// Get current review request status for debugging
    func getReviewStatus() -> (requestCount: Int, lastRequestDate: Date?, firstLaunchDate: Date?) {
        let count = UserDefaults.standard.integer(forKey: reviewRequestKey)
        let lastRequest = UserDefaults.standard.object(forKey: lastReviewRequestKey) as? Date
        let firstLaunch = UserDefaults.standard.object(forKey: firstLaunchKey) as? Date
        return (count, lastRequest, firstLaunch)
    }
    
    /// Force request review (for testing purposes only)
    func forceRequestReview() {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
                print("Could not find active window scene")
                return
            }
            
            SKStoreReviewController.requestReview(in: scene)
            print("Force review request triggered")
        }
    }
}
