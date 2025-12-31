//
//  ReminderSettingsView.swift
//  MomBabyLogger
//
//  Settings view for breast feeding reminders
//

import SwiftUI

struct ReminderSettingsView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @State private var settings = ReminderSettings.load()
    @State private var showingPermissionAlert = false
    @State private var nextReminderDate: Date?
    
    var body: some View {
        Form {
            // Status Section
            Section {
                HStack {
                    Image(systemName: notificationManager.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(notificationManager.isAuthorized ? .green : .orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notification Status")
                            .font(.headline)
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                
                if !notificationManager.isAuthorized {
                    Button(action: handlePermissionRequest) {
                        HStack {
                            Image(systemName: "bell.badge")
                            Text(notificationManager.canRequestAuthorization ? "Enable Notifications" : "Open Settings")
                        }
                    }
                }
            }
            
            // Reminder Settings Section
            Section(header: Text("Reminder Settings")) {
                Toggle("Enable Reminders", isOn: $settings.isEnabled)
                    .onChange(of: settings.isEnabled) { _, newValue in
                        settings.save()
                        if !newValue {
                            Task {
                                await notificationManager.cancelReminder()
                                nextReminderDate = nil
                            }
                        }
                    }
                
                if settings.isEnabled {
                    Picker("Reminder Interval", selection: $settings.intervalHours) {
                        ForEach(ReminderSettings.intervalOptions, id: \.self) { hours in
                            Text(formatInterval(hours))
                                .tag(hours)
                        }
                    }
                    .onChange(of: settings.intervalHours) { _, _ in
                        settings.save()
                    }
                }
            }
            .disabled(!notificationManager.isAuthorized)
            
            // Next Reminder Section
            if settings.isEnabled && notificationManager.isAuthorized {
                Section(header: Text("Next Reminder")) {
                    if let nextDate = nextReminderDate {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(nextDate, style: .date)
                                    .font(.subheadline)
                                Text(nextDate, style: .time)
                                    .font(.headline)
                            }
                            Spacer()
                            Text(timeUntilText(nextDate))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text("No reminder scheduled")
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Log any feeding (breast, bottle, or formula) to schedule a reminder")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Button(action: {
                        Task {
                            await updateNextReminderDate()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Status")
                        }
                    }
                }
            }
            
            // Info Section
            Section(header: Text("How It Works")) {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Log **any feeding** (breast, bottle, or formula) in the Log tab")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "1.circle.fill")
                            .foregroundColor(.blue)
                    }
                    
                    Label {
                        Text("A reminder will be scheduled \(settings.intervalDisplayText) later")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "2.circle.fill")
                            .foregroundColor(.blue)
                    }
                    
                    Label {
                        Text("You'll get a notification when it's time to feed again")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "3.circle.fill")
                            .foregroundColor(.blue)
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    Text("✅ Works with breast, bottle, and formula feedings")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.vertical, 2)
                    
                    Text("Each new feeding automatically reschedules the reminder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // Troubleshooting Section
            if settings.isEnabled && notificationManager.isAuthorized && nextReminderDate == nil {
                Section(header: Text("Troubleshooting")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("Make sure you've logged at least one feeding")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                        }
                        
                        Label {
                            Text("Any feeding type works (breast, bottle, or formula)")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "heart.circle")
                                .foregroundColor(.blue)
                        }
                        
                        Label {
                            Text("Reminders appear after returning to this screen")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                        }
                    }
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Feeding Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await notificationManager.checkAuthorizationStatus()
            await updateNextReminderDate()
        }
        .onAppear {
            Task {
                await updateNextReminderDate()
            }
        }
        .alert("Notification Permission", isPresented: $showingPermissionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enable notifications in Settings to receive breast feeding reminders.")
        }
    }
    
    // MARK: - Helper Methods
    
    private var statusText: String {
        switch notificationManager.authorizationStatus {
        case .authorized:
            return "Notifications enabled"
        case .denied:
            return "Notifications disabled in Settings"
        case .notDetermined:
            return "Notifications not yet enabled"
        case .provisional:
            return "Provisional notifications enabled"
        case .ephemeral:
            return "Temporary notifications enabled"
        @unknown default:
            return "Unknown status"
        }
    }
    
    private func formatInterval(_ hours: Double) -> String {
        if hours.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(hours)) hours"
        } else {
            return "\(hours) hours"
        }
    }
    
    private func timeUntilText(_ date: Date) -> String {
        let now = Date()
        let interval = date.timeIntervalSince(now)
        
        if interval < 0 {
            return "Past due"
        }
        
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            return "in \(hours)h \(minutes)m"
        } else {
            return "in \(minutes)m"
        }
    }
    
    private func handlePermissionRequest() {
        if notificationManager.canRequestAuthorization {
            Task {
                let granted = await notificationManager.requestAuthorization()
                if !granted {
                    showingPermissionAlert = true
                }
            }
        } else {
            notificationManager.openAppSettings()
        }
    }
    
    private func updateNextReminderDate() async {
        nextReminderDate = await notificationManager.getNextReminderDate()
    }
}

#Preview {
    NavigationView {
        ReminderSettingsView()
    }
}
