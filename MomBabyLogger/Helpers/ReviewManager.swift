//
//  ReviewManager.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/15/25.
//

import Foundation
import StoreKit

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
        // Don't ask too frequently - Apple limits to 3 times per year
        guard canRequestReview() else { return }

        // Trigger conditions (any one of these)
        let shouldRequest = entryCount == 10 ||  // After 10 entries
                           entryCount == 25 ||  // After 25 entries
                           entryCount == 50     // After 50 entries

        guard shouldRequest else { return }

        // Request review
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)

            // Track that we requested
            incrementReviewRequestCount()
            UserDefaults.standard.set(Date(), forKey: lastReviewRequestKey)
        }
    }

    /// Check if we can request a review based on frequency limits
    private func canRequestReview() -> Bool {
        // Check review request count (max 3 per year)
        let requestCount = UserDefaults.standard.integer(forKey: reviewRequestKey)
        guard requestCount < 3 else { return false }

        // Check if enough time has passed since last request (at least 2 months)
        if let lastRequest = UserDefaults.standard.object(forKey: lastReviewRequestKey) as? Date {
            let twoMonthsAgo = Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()
            guard lastRequest < twoMonthsAgo else { return false }
        }

        // Check if user has been using app for at least 3 days
        if let firstLaunch = UserDefaults.standard.object(forKey: firstLaunchKey) as? Date {
            let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
            guard firstLaunch < threeDaysAgo else { return false }
        }

        return true
    }

    /// Increment the review request counter
    private func incrementReviewRequestCount() {
        let currentCount = UserDefaults.standard.integer(forKey: reviewRequestKey)
        UserDefaults.standard.set(currentCount + 1, forKey: reviewRequestKey)
    }

    /// Reset review request count (call this at the start of a new year)
    func resetYearlyCount() {
        UserDefaults.standard.set(0, forKey: reviewRequestKey)
    }
}
