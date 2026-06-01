//
//  ActivityRowView.swift
//  MomBabyLogger
//

import SwiftUI

struct ActivityRowView: View {
    let entry: EntryWrapper
    var isPartnerEntry: Bool = false

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.type.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.18))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(timeFormatter.string(from: entry.timestamp))
                        .font(AppTheme.Typography.bodyMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.Colors.primaryText)

                    if isPartnerEntry {
                        Text("Partner")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(AppTheme.Colors.primaryAction)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.Colors.primaryAction.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Spacer()
                }

                Text(entry.displayText)
                    .font(AppTheme.Typography.bodySmall)
                    .foregroundColor(AppTheme.Colors.secondaryText)

                if let notes = entryNotes, !notes.isEmpty {
                    Text(notes)
                        .font(AppTheme.Typography.labelSmall)
                        .foregroundColor(AppTheme.Colors.tertiaryText)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var iconColor: Color {
        switch entry.type {
        case .breastFeeding:
            return AppTheme.Colors.breastFeeding
        case .bottleFeeding:
            return AppTheme.Colors.bottleFeeding
        case .formulaFeeding:
            return AppTheme.Colors.formulaFeeding
        case .wetDiaper:
            return AppTheme.Colors.wetDiaper
        case .poopDiaper:
            return AppTheme.Colors.poopDiaper
        case .mixedDiaper:
            return AppTheme.Colors.mixedDiaper
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
