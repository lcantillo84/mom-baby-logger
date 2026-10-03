//
//  FirstLaunchNotice.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// Shows a one-time notice the first time the app opens (for new
// installs AND for existing users after updating to 1.7.3):
// "Mommy's Log is a logging tool, not medical advice…"
// Tapping OK saves a flag so it never shows again.
//
// Added in 1.7.3 for compliance (Apple guideline 1.4.1: remind
// users to check with a doctor). It only reads/writes its own
// UserDefaults key and touches no app data.
//
// If the wording ever changes in a meaningful way, bump the key
// (…V1 → …V2) so everyone sees the new text once.
// ─────────────────────────────────────────────────────────────

import SwiftUI

struct FirstLaunchNoticeModifier: ViewModifier {

    @AppStorage("mommyslog.medicalNoticeSeenV1") private var hasSeenNotice = false

    func body(content: Content) -> some View {
        content
            .alert("Before you start", isPresented: Binding(
                get: { !hasSeenNotice },
                set: { isShowing in if !isShowing { hasSeenNotice = true } }
            )) {
                Button("OK") { hasSeenNotice = true }
            } message: {
                Text("Mommy's Log is a logging tool, not medical advice. Always check with your pediatrician about your baby's health.")
            }
    }
}

extension View {
    /// Shows the one-time "logging tool, not medical advice" notice.
    func firstLaunchNotice() -> some View {
        modifier(FirstLaunchNoticeModifier())
    }
}
