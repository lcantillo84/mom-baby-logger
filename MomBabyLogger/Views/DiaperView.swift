//
//  DiaperView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct DiaperView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var notes: String = ""
    @State private var showingConfirmation = false
    @State private var lastLoggedType: ActivityType?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Text("What type of diaper change?")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .padding(.top)

                    // Three large buttons for diaper types
                    VStack(spacing: 20) {
                        diaperButton(
                            type: .wetDiaper,
                            icon: "drop.triangle",
                            color: .blue,
                            title: "Wet"
                        )

                        diaperButton(
                            type: .poopDiaper,
                            icon: "leaf.fill",
                            color: .brown,
                            title: "Poop"
                        )

                        diaperButton(
                            type: .mixedDiaper,
                            icon: "drop.triangle.fill",
                            color: .purple,
                            title: "Both"
                        )
                    }
                    .padding(.horizontal)

                    // Notes section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        TextEditor(text: $notes)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.vertical)
            }
            .navigationTitle("Diaper Change")
            .alert("Diaper Change Logged", isPresented: $showingConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                if let type = lastLoggedType {
                    Text("\(type.displayName) has been successfully recorded")
                }
            }
        }
    }

    // MARK: - Diaper Button

    private func diaperButton(type: ActivityType, icon: String, color: Color, title: String) -> some View {
        Button(action: {
            logDiaperChange(type: type)
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text("Tap to log")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logging Function

    private func logDiaperChange(type: ActivityType) {
        let entry = DiaperEntry(
            type: type,
            notes: notes.isEmpty ? nil : notes
        )
        dataStore.addDiaper(entry)

        lastLoggedType = type
        notes = ""
        showingConfirmation = true
    }
}

#Preview {
    DiaperView()
        .environmentObject(DataStore())
}
