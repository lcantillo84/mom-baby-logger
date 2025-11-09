//
//  ActivityRowView.swift
//  MomBabyLogger
//
//  Created by Lilianne Cantillo on 11/9/25.
//

import SwiftUI

struct ActivityRowView: View {
    let entry: EntryWrapper

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: entry.type.icon)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.15))
                .clipShape(Circle())

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(timeFormatter.string(from: entry.timestamp))
                    .font(.headline)

                Text(entry.displayText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Show notes if available
                if let notes = entryNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var iconColor: Color {
        switch entry.type {
        case .breastFeeding:
            return .pink
        case .bottleFeeding, .formulaFeeding:
            return .blue
        case .wetDiaper:
            return .cyan
        case .poopDiaper:
            return .brown
        case .mixedDiaper:
            return .purple
        }
    }

    private var entryNotes: String? {
        switch entry {
        case .feeding(let feedingEntry):
            return feedingEntry.notes
        case .diaper(let diaperEntry):
            return diaperEntry.notes
        }
    }
}
