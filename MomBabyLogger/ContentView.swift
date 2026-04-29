//
//  ContentView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct ContentView: View {
    // DataStore is now owned by MomBabyLoggerApp and passed down via environment.
    // @EnvironmentObject reads it from there instead of creating a second copy.
    @EnvironmentObject private var dataStore: DataStore
    @State private var showWhatsNew = false
    @State private var whatsNewContent: WhatsNewContent?

    var body: some View {
        TabView {
            FeedingView()
                .tabItem {
                    Label("Feeding", systemImage: "drop.fill")
                }

            DiaperView()
                .tabItem {
                    Label("Diaper", systemImage: "leaf.fill")
                }

            TodayView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }

            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "chart.bar.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(AppTheme.Colors.tabActive)
        .onAppear {
            checkForAppUpdate()
        }
        .sheet(isPresented: $showWhatsNew) {
            if let content = whatsNewContent {
                WhatsNewView(content: content)
            }
        }
    }

    // MARK: - Version Check

    private func checkForAppUpdate() {
        let versionManager = AppVersionManager.shared

        // Check if we should show What's New
        if versionManager.shouldShowWhatsNew(),
           let content = versionManager.getCurrentWhatsNewContent() {
            whatsNewContent = content
            showWhatsNew = true
        }

        // Update the last saved version
        versionManager.updateLastVersion()
    }
}

#Preview {
    ContentView()
        .environmentObject(DataStore())
}
