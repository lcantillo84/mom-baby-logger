//
//  AIDigestCard.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// This is the "showstopper" AI card shown in InsightsView (Pro only).
//
// The card has four visual states:
//
//  1. IDLE — "Generate Summary" button, nothing generated yet
//  2. LOADING — spinner + "Analyzing patterns..." while Claude responds
//  3. STREAMING — text appears word by word as Claude sends it
//     (same effect as ChatGPT typing in real time)
//  4. ERROR — gentle error message + "Try Again" button
//
// The text streaming works because AIInsightsService.streamedText
// is a @Published String. Every time Claude sends a word/token,
// the service appends it to streamedText. This view observes that
// property via @ObservedObject, so SwiftUI re-renders the Text view
// after each append — producing the live typing effect.
//
// The [AI] badge, [BETA] pill, and medical disclaimer are always
// visible so the user always knows what kind of content this is.
// ─────────────────────────────────────────────────────────────

import SwiftUI

struct AIDigestCard: View {

    let entries: [EntryWrapper]

    // 📖 SWIFT CONCEPT: @ObservedObject
    // This view "watches" the shared AIInsightsService singleton.
    // When streamedText, isLoading, or errorMessage change, SwiftUI
    // automatically re-renders this view. No manual refresh needed.
    @ObservedObject private var ai = AIInsightsService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {

            // ── Header (always visible) ────────────────────────────────────
            header

            Divider()
                .padding(.horizontal, AppTheme.Spacing.md)

            // ── Content area — switches between the 4 states ───────────────
            contentArea
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.xs)

            // ── Disclaimer (always visible below content) ──────────────────
            // This is the third layer of medical safety (after system prompt
            // and [AI] badge). Even if the model misbehaves, the UI always
            // shows a clear "not medical advice" statement.
            if !ai.streamedText.isEmpty || ai.isLoading {
                disclaimer
            }
        }
        // Card styling matches feedingChartCard and diaperChartCard exactly
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.Colors.cardBackground)
        .cornerRadius(AppTheme.Radius.card)
        .modifier(CardShadow())
        .padding(.horizontal)
    }

    // ─── Header ───────────────────────────────────────────────────────────
    private var header: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppTheme.Colors.primaryAction)

            Text("AI Daily Digest")
                .font(AppTheme.Typography.titleSmall)
                .foregroundColor(AppTheme.Colors.primaryText)

            Spacer()

            // [BETA] pill — signals feature is in early access
            Text("BETA")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(AppTheme.Colors.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.Colors.secondaryText.opacity(0.12))
                .cornerRadius(AppTheme.Radius.pill)

            // [AI] badge — clearly labels AI-generated content
            Text("AI")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(AppTheme.Colors.primaryAction)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(AppTheme.Colors.primaryAction.opacity(0.12))
                .cornerRadius(AppTheme.Radius.pill)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    // ─── Content Area (state machine) ─────────────────────────────────────
    // 📖 SWIFT CONCEPT: Computed property as a view
    // This @ViewBuilder property returns different views based on state.
    // Swift evaluates this every re-render, so it always shows the right state.
    @ViewBuilder
    private var contentArea: some View {
        if let error = ai.errorMessage {
            // STATE 4: ERROR
            errorView(message: error)

        } else if ai.isLoading && ai.streamedText.isEmpty {
            // STATE 2: LOADING (spinner before first token arrives)
            loadingView

        } else if !ai.streamedText.isEmpty {
            // STATE 3: STREAMING / DONE
            // streamedText grows token by token while isLoading is true,
            // then stops growing when the stream ends (isLoading = false).
            streamedTextView

        } else {
            // STATE 1: IDLE (nothing generated yet)
            idleView
        }
    }

    // ─── State 1: Idle ────────────────────────────────────────────────────
    private var idleView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Get a plain-English summary of today's feeding and diaper patterns.")
                .font(AppTheme.Typography.bodyMedium)
                .foregroundColor(AppTheme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    await ai.generateDailySummary(from: entries)
                }
            } label: {
                Label("Generate Summary", systemImage: "sparkles")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, AppTheme.Spacing.xs)
        }
    }

    // ─── State 2: Loading ─────────────────────────────────────────────────
    private var loadingView: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ProgressView()
                .tint(AppTheme.Colors.primaryAction)
            Text("Analyzing patterns…")
                .font(AppTheme.Typography.bodyMedium)
                .foregroundColor(AppTheme.Colors.secondaryText)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    // ─── State 3: Streaming / Done ────────────────────────────────────────
    private var streamedTextView: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // 📖 SWIFT CONCEPT: Text with @Published string
            // Every time ai.streamedText gains a new character/word,
            // this Text view re-renders with the longer string.
            // The cursor indicator while loading shows it's still streaming.
            Text(ai.streamedText + (ai.isLoading ? "▋" : ""))
                .font(AppTheme.Typography.bodyMedium)
                .foregroundColor(AppTheme.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.default, value: ai.streamedText)

            // "Regenerate" only shown after streaming is complete.
            // force: true bypasses cache — user explicitly wants a fresh call.
            if !ai.isLoading {
                Button {
                    Task {
                        await ai.generateDailySummary(from: entries, force: true)
                    }
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(AppTheme.Typography.bodyMedium)
                        .foregroundColor(AppTheme.Colors.primaryAction)
                }
            }
        }
    }

    // ─── State 4: Error ───────────────────────────────────────────────────
    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(AppTheme.Colors.destructiveAction)
                Text(message)
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.Colors.destructiveAction)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                ai.errorMessage = nil   // clear error, return to idle
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }
        }
    }

    // ─── Disclaimer ───────────────────────────────────────────────────────
    private var disclaimer: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.xs) {
            Image(systemName: "stethoscope")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.Colors.tertiaryText)
            Text("Pattern summary only — not medical advice. Always consult your pediatrician.")
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.bottom, AppTheme.Spacing.sm)
    }
}

#Preview {
    ScrollView {
        AIDigestCard(entries: [])
    }
    .background(AppTheme.Colors.appBackground)
}
