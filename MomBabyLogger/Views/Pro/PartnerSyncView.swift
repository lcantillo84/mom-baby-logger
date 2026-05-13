//
//  PartnerSyncView.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// WHAT THIS FILE DOES (plain English):
//
// This is the sync settings screen that PRO users see.
// (Non-Pro users see ProGateView instead.)
//
// It shows:
//  • Current sync status (badge: syncing / synced / error)
//  • "Invite Partner" button → opens iOS share sheet
//  • "Connected" status if partner accepted the invite
//  • "Disconnect Partner" button if connected
//
// This screen is the main control panel for the Partner Sync feature.
// ─────────────────────────────────────────────────────────────

import CloudKit
import SwiftUI
import UIKit

struct PartnerSyncView: View {

    @EnvironmentObject private var dataStore: DataStore
    @ObservedObject private var sync    = SyncStateManager.shared
    @ObservedObject private var sharing = SharingManager.shared

    // 📖 SWIFT CONCEPT: @State
    // Local, temporary UI state. Not saved to disk. Only this view owns it.
    @State private var showDisconnectConfirm   = false
    @State private var shareURLForPresentation: URL? = nil

    var body: some View {
        List {

            // ── Error Banner ──────────────────────────────────────────────
            if let errorMessage = sharing.errorMessage {
                Section {
                    Button {
                        sharing.errorMessage = nil
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(AppTheme.Colors.destructiveAction)
                            Text(errorMessage)
                                .font(AppTheme.Typography.bodyMedium)
                                .foregroundColor(AppTheme.Colors.destructiveAction)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(AppTheme.Colors.tertiaryText)
                        }
                    }
                }
            }

            // ── Sync Status Card ──────────────────────────────────────────
            Section {
                syncStatusRow
            }

            // ── Partner Status ────────────────────────────────────────────
            Section(header: Text(sync.isParticipant ? "Shared Log" : "Partner Access")) {
                if sync.isParticipant {
                    participantStatusRow
                } else if sync.isPartnerConnected {
                    connectedRow
                } else if sharing.activeShare != nil {
                    pendingRow
                } else {
                    inviteRow
                }
            }

            // ── How It Works (owners only) ────────────────────────────────
            if !sync.isParticipant {
                Section(header: Text("How It Works")) {
                    howItWorksContent
                }
            }

            // ── Leave / Disconnect / Cancel ───────────────────────────────
            if sync.isParticipant {
                Section {
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        Label("Leave Shared Log", systemImage: "person.badge.minus")
                    }
                }
            } else if sync.isPartnerConnected {
                Section {
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        Label("Disconnect Partner", systemImage: "person.badge.minus")
                    }
                }
            } else if sharing.activeShare != nil {
                Section {
                    Button(role: .destructive) {
                        showDisconnectConfirm = true
                    } label: {
                        Label("Cancel Invite", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.appBackground)
        .navigationTitle("Partner Sync")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Participants don't own a share — skip loadExistingShare to avoid errors.
            if !sync.isParticipant {
                await sharing.loadExistingShare()
            }
            await CloudKitManager.shared.fetchChanges()
        }
        .sheet(isPresented: Binding(
            get: { shareURLForPresentation != nil },
            set: { if !$0 { shareURLForPresentation = nil } }
        )) {
            if let url = shareURLForPresentation {
                ActivityShareSheet(url: url)
            }
        }
        .confirmationDialog(
            sync.isParticipant ? "Leave Shared Log?" : sync.isPartnerConnected ? "Disconnect Partner?" : "Cancel Invite?",
            isPresented: $showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button(sync.isParticipant ? "Leave" : sync.isPartnerConnected ? "Disconnect" : "Cancel Invite", role: .destructive) {
                Task {
                    if sync.isParticipant {
                        await sharing.leaveShare()
                    } else {
                        await sharing.revokeShare()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(sync.isParticipant
                 ? "You will lose access to the shared baby log."
                 : sync.isPartnerConnected
                    ? "Your partner will immediately lose access to the shared logs."
                    : "The invite link will stop working. You can send a new invite anytime.")
        }
    }

    // MARK: - Row Views

    private var syncStatusRow: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(sync.syncStatus.color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: sync.syncStatus.iconName)
                        .font(.system(size: 18))
                        .foregroundColor(sync.syncStatus.color)
                        // Spinning animation while syncing
                        .rotationEffect(sync.syncStatus == .syncing ? .degrees(360) : .degrees(0))
                        .animation(
                            sync.syncStatus == .syncing
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: sync.syncStatus == .syncing
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Sync")
                        .font(AppTheme.Typography.bodyLarge)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.Colors.primaryText)
                    Text(sync.syncStatus.label)
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundColor(sync.syncStatus.color)
                    if let date = sync.lastSyncedDate {
                        Text("Last synced \(date.relativeFormatted)")
                            .font(AppTheme.Typography.labelSmall)
                            .foregroundColor(AppTheme.Colors.tertiaryText)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    private var pendingRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.primaryAction.opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppTheme.Colors.primaryAction)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite Sent")
                        .font(AppTheme.Typography.bodyLarge)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.Colors.primaryText)
                    Text("Waiting for partner to accept")
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundColor(AppTheme.Colors.secondaryText)
                }
                Spacer()
            }

            Button {
                Task { shareURLForPresentation = await sharing.getShareURL() }
            } label: {
                Label("Resend Invite", systemImage: "arrow.clockwise")
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }
            .disabled(sharing.isLoading)
        }
        .padding(.vertical, 6)
    }

    private var inviteRow: some View {
        Button {
            Task { shareURLForPresentation = await sharing.getShareURL() }
        } label: {
            HStack {
                Label("Invite Partner or Nanny", systemImage: "person.badge.plus")
                    .foregroundColor(AppTheme.Colors.primaryAction)
                Spacer()
                if sharing.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(AppTheme.Colors.tertiaryText)
                }
            }
        }
        .disabled(sharing.isLoading)
    }

    // Shown on Phone 2 (the partner / nanny who accepted the invite).
    private var participantStatusRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.Colors.primaryAction.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppTheme.Colors.primaryAction)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected to Shared Log")
                        .font(AppTheme.Typography.bodyLarge)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.Colors.primaryText)
                    Text("You're viewing and syncing the shared baby log")
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundColor(AppTheme.Colors.secondaryText)
                }
                Spacer()
            }

            Button {
                Task { await CloudKitManager.shared.fetchChanges() }
            } label: {
                Label("Refresh Logs", systemImage: "arrow.clockwise")
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }
            .disabled(sync.syncStatus == .syncing)
        }
        .padding(.vertical, 6)
    }

    private var connectedRow: some View {
        let participants = sharing.activeShare?.participants
            .filter { $0.role != .owner } ?? []

        return VStack(alignment: .leading, spacing: 10) {
            if participants.isEmpty {
                participantTile(name: "Partner", detail: "Live sync is active")
            } else {
                ForEach(participants, id: \.userIdentity.userRecordID?.recordName) { p in
                    let name = p.userIdentity.nameComponents.map {
                        PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                    } ?? "Partner"
                    let detail = p.acceptanceStatus == .accepted
                        ? "Live sync is active"
                        : "Invite pending acceptance"
                    participantTile(name: name, detail: detail)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func participantTile(name: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.Colors.primaryAction.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(AppTheme.Typography.bodyLarge)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.Colors.primaryText)
                Text(detail)
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.secondaryText)
            }
            Spacer()
        }
    }

    private var howItWorksContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepRow(number: "1", text: "Tap **Invite Partner** — iOS opens a share sheet")
            stepRow(number: "2", text: "Send the link via iMessage or any app")
            stepRow(number: "3", text: "Partner taps the link and accepts — done!")
            stepRow(number: "4", text: "All logs sync automatically, both ways")

            Divider()

            Label("Both partners can view and log entries — changes sync both ways",
                  systemImage: "lock.shield.fill")
                .font(AppTheme.Typography.labelSmall)
                .foregroundColor(AppTheme.Colors.secondaryText)
        }
        .padding(.vertical, 8)
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.Colors.primaryAction)
                .frame(width: 22, height: 22)
                .background(AppTheme.Colors.primaryAction.opacity(0.10))
                .clipShape(Circle())

            // 📖 SWIFT CONCEPT: AttributedString / markdown in Text
            // Wrapping the string in `try? AttributedString(markdown:)` lets
            // you use **bold** syntax inline. Simple and readable.
            if let attributed = try? AttributedString(markdown: text) {
                Text(attributed)
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(text)
                    .font(AppTheme.Typography.bodyMedium)
                    .foregroundColor(AppTheme.Colors.secondaryText)
            }
        }
    }
}

private extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// Wraps UIActivityViewController so SwiftUI can present it via .sheet().
// iOS recognises the cloudkit.com URL and routes it to the app's share-acceptance
// handler when the recipient taps the link.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        PartnerSyncView()
            .environmentObject(DataStore())
    }
    .background(AppTheme.Colors.appBackground)
}
