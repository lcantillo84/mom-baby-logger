//
//  ContentView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var dataStore = DataStore()

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

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .environmentObject(dataStore)
    }
}

#Preview {
    ContentView()
}
