//
//  MomBabyLoggerApp.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

@main
struct MomBabyLoggerApp: App {

    init() {
        // Track app open for analytics
        AnalyticsManager.shared.trackAppOpen()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
