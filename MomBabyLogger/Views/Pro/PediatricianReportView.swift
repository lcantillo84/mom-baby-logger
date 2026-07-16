//
//  PediatricianReportView.swift
//  MomBabyLogger
//
// ─────────────────────────────────────────────────────────────
// PRO FEATURE: one-tap "doctor visit" report.
//
// Answers the exact questions a pediatrician asks at checkups —
// "How many feeds a day? How many ounces? How many wet diapers?" —
// over the last 7 or 30 days, and exports the whole thing as a
// share-ready image (Messages, Mail, print, save to Photos).
//
// Pure on-device math over DataStore (read-only; uses DailyStats).
// No network, no API, no new persistence. Visual style mirrors
// InsightsView (same cards, chart colors, and AppTheme tokens).
// ─────────────────────────────────────────────────────────────

import Charts
import SwiftUI

struct PediatricianReportView: View {
    @EnvironmentObject var dataStore: DataStore

    @State private var timeframe: ReportTimeframe = .week
    @State private var renderedImage: Image?
    @State private var pdfURL: URL?
    @State private var isGeneratingReport = false

    // Optional baby profile — on-device only (set in Settings; see the privacy
    // note there). Empty/0 = not set, header shows nothing.
    @AppStorage("mommyslog.babyName") private var babyName: String = ""
    @AppStorage("mommyslog.babyBirthday") private var babyBirthdayInterval: Double = 0

    // "Emma — 4 months old" / "Emma" / nil when no profile is set.
    private var babyLine: String? {
        let name = babyName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        guard babyBirthdayInterval > 0 else { return name }
        let birthday = Date(timeIntervalSince1970: babyBirthdayInterval)
        let components = Calendar.current.dateComponents([.month, .weekOfYear, .year], from: birthday, to: Date())
        let months = components.month ?? 0
        let age: String
        if months < 2 {
            let weeks = max(components.weekOfYear ?? 0, 0)
            age = weeks == 1 ? "1 week old" : "\(weeks) weeks old"
        } else if months < 24 {
            age = "\(months) months old"
        } else {
            let years = months / 12
            age = years == 1 ? "1 year old" : "\(years) years old"
        }
        return "\(name) — \(age)"
    }

    enum ReportTimeframe: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        var id: Int { rawValue }
        var label: String { self == .week ? "Last 7 Days" : "Last 30 Days" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.lg) {
                Picker("Timeframe", selection: $timeframe) {
                    ForEach(ReportTimeframe.allCases) { tf in
                        Text(tf.label).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Always visible near the top — WITHOUT scrolling — so the user sees
                // it immediately. The matching indicator by the Share button (further
                // down) is easy to miss since it's below the charts.
                if isGeneratingReport {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Preparing your report…")
                            .font(AppTheme.Typography.labelMedium)
                    }
                    .foregroundColor(AppTheme.Colors.secondaryText)
                    .padding(.horizontal)
                    .transition(.opacity)
                }

                reportCard
                    .padding(.horizontal)

                shareButton
                    .padding(.horizontal)
                    .padding(.bottom, AppTheme.Spacing.xl)
            }
            .padding(.top, AppTheme.Spacing.md)
        }
        .background(AppTheme.Colors.appBackground.ignoresSafeArea())
        .navigationTitle("Doctor Visit Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(AppTheme.Colors.appBackground, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .onAppear { regenerateShareAssets() }
        .onChange(of: timeframe) { _, _ in regenerateShareAssets() }
        // Watch the ENTRIES themselves (Equatable), not just the count — an edit
        // keeps the count identical but must still refresh the share image/PDF.
        .onChange(of: dataStore.entries) { _, _ in regenerateShareAssets() }
    }

    // MARK: - Data

    private var days: [ReportDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<timeframe.rawValue).reversed().map { i in
            let start = calendar.date(byAdding: .day, value: -i, to: today)!
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            let stats = DailyStats(from: dataStore.entries(from: start, to: end))
            return ReportDay(
                date: start,
                feedings: stats.totalFeedings,
                totalOz: stats.bottleFeedingTotalOz + stats.formulaFeedingTotalOz,
                nursingMinutes: stats.breastFeedingTotalMinutes,
                // Pediatric convention: mixed diapers count as both wet AND dirty.
                wetDiapers: stats.wetCount + stats.mixedCount,
                dirtyDiapers: stats.poopCount + stats.mixedCount
            )
        }
    }

    private var summary: ReportSummary { ReportSummary(days: days, entries: dataStore.entries) }

    // MARK: - The Report (also what gets rendered to the share image)

    private var reportCard: some View {
        ReportCardView(days: days, summary: summary, timeframe: timeframe, babyLine: babyLine)
    }

    // MARK: - Share

    private var shareButton: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if isGeneratingReport {
                // Visible feedback while the 3x image + PDF render — without this
                // the screen looks frozen and the user doesn't know to wait.
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)
                    Text("Preparing report…")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.Colors.primaryAction.opacity(0.55))
                .foregroundColor(.white)
                .cornerRadius(AppTheme.Radius.card)
            } else if let renderedImage {
                ShareLink(
                    item: renderedImage,
                    preview: SharePreview("Doctor Visit Report", image: renderedImage)
                ) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Report")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    regenerateShareAssets()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Report")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            // PDF for printing / the pediatrician's office records.
            if let pdfURL {
                ShareLink(item: pdfURL) {
                    HStack {
                        Image(systemName: "doc.richtext")
                        Text("Save as PDF")
                    }
                    .frame(maxWidth: .infinity)
                }
                .font(AppTheme.Typography.labelMedium)
                .foregroundColor(AppTheme.Colors.primaryAction)
                .padding(.vertical, 6)
            }
        }
    }

    // Public entry point: shows the "Preparing report…" state, lets SwiftUI draw
    // it (one yield + a beat), then runs the render. ImageRenderer must run on the
    // main actor, so the render itself briefly blocks — the visible state change
    // before it is what tells the user the app is working, not frozen.
    private func regenerateShareAssets() {
        guard !isGeneratingReport else { return }
        withAnimation { isGeneratingReport = true }
        renderedImage = nil
        pdfURL = nil
        Task { @MainActor in
            await Task.yield()
            // Guarantee the "Preparing…" state is on screen long enough to actually
            // register with the user, even when the render itself finishes in a few
            // milliseconds (common on a fast device / Release build).
            try? await Task.sleep(nanoseconds: 500_000_000)
            renderShareImage()
            withAnimation { isGeneratingReport = false }
        }
    }

    // Renders the report card to a crisp 3x image + a vector PDF for sharing/printing.
    @MainActor
    private func renderShareImage() {
        let content = ReportCardView(days: days, summary: summary, timeframe: timeframe, babyLine: babyLine)
            .frame(width: 420)
            .background(AppTheme.Colors.appBackground)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }

        // PDF: vector output — prints razor-sharp at any size.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Doctor Visit Report.pdf")
        renderer.render { size, renderInContext in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let pdfContext = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
            pdfContext.beginPDFPage(nil)
            renderInContext(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
        }
        pdfURL = FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

// MARK: - Report Day / Summary models

private struct ReportDay: Identifiable {
    let date: Date
    let feedings: Int
    let totalOz: Double
    let nursingMinutes: Int
    let wetDiapers: Int
    let dirtyDiapers: Int
    var id: Date { date }
}

private struct ReportSummary {
    let avgFeedings: Double
    let avgOz: Double
    let avgNursingMinutes: Double
    let avgWet: Double
    let avgDirty: Double
    let avgFeedGap: TimeInterval?   // mean time between feeds across the period
    let hasOz: Bool
    let hasNursing: Bool

    init(days: [ReportDay], entries: [EntryWrapper]) {
        let n = Double(max(days.count, 1))
        avgFeedings = Double(days.reduce(0) { $0 + $1.feedings }) / n
        avgOz = days.reduce(0) { $0 + $1.totalOz } / n
        avgNursingMinutes = Double(days.reduce(0) { $0 + $1.nursingMinutes }) / n
        avgWet = Double(days.reduce(0) { $0 + $1.wetDiapers }) / n
        avgDirty = Double(days.reduce(0) { $0 + $1.dirtyDiapers }) / n
        hasOz = days.contains { $0.totalOz > 0 }
        hasNursing = days.contains { $0.nursingMinutes > 0 }

        // Average gap between consecutive feedings inside the report window.
        guard let firstDay = days.first?.date else { avgFeedGap = nil; return }
        let feedTimes = entries.compactMap { entry -> Date? in
            if case .feeding = entry, entry.timestamp >= firstDay { return entry.timestamp }
            return nil
        }.sorted()
        guard feedTimes.count >= 2 else { avgFeedGap = nil; return }
        let gaps = zip(feedTimes.dropFirst(), feedTimes).map { $0.timeIntervalSince($1) }
        avgFeedGap = gaps.reduce(0, +) / Double(gaps.count)
    }

    var feedGapText: String {
        guard let gap = avgFeedGap else { return "—" }
        let hours = Int(gap) / 3600
        let minutes = (Int(gap) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

// MARK: - The card itself (separate view so ImageRenderer can render it standalone)

private struct ReportCardView: View {
    let days: [ReportDay]
    let summary: ReportSummary
    let timeframe: PediatricianReportView.ReportTimeframe
    let babyLine: String?

    private var dateRangeText: String {
        guard let first = days.first?.date, let last = days.last?.date else { return "" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let year = DateFormatter()
        year.dateFormat = "MMM d, yyyy"
        return "\(fmt.string(from: first)) – \(year.string(from: last))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            header
            statTiles
            feedingsChart
            if summary.hasOz { ozChart }
            diapersChart
            footer
        }
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.Colors.cardBackground)
        .cornerRadius(AppTheme.Radius.card)
        .modifier(CardShadow())
    }

    // ── Header ──────────────────────────────────────────────────────────────

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "stethoscope")
                    .foregroundColor(AppTheme.Colors.primaryAction)
                Text("Doctor Visit Report")
                    .font(AppTheme.Typography.titleMedium)
                    .foregroundColor(AppTheme.Colors.primaryText)
            }
            if let babyLine {
                Text(babyLine)
                    .font(AppTheme.Typography.sectionHeader)
                    .foregroundColor(AppTheme.Colors.primaryAction)
            }
            Text(dateRangeText)
                .font(AppTheme.Typography.labelMedium)
                .foregroundColor(AppTheme.Colors.secondaryText)
        }
        .padding(.horizontal)
    }

    // ── Stat tiles ──────────────────────────────────────────────────────────

    private var statTiles: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                statTile(value: String(format: "%.1f", summary.avgFeedings),
                         label: "Feeds / day", color: AppTheme.Colors.primaryAction)
                if summary.hasOz {
                    statTile(value: String(format: "%.1f oz", summary.avgOz),
                             label: "Bottle+formula / day", color: AppTheme.Colors.bottleFeeding)
                } else {
                    statTile(value: summary.feedGapText,
                             label: "Between feeds", color: AppTheme.Colors.bottleFeeding)
                }
                if summary.hasNursing {
                    statTile(value: String(format: "%.0f min", summary.avgNursingMinutes),
                             label: "Nursing / day", color: AppTheme.Colors.primaryAction)
                }
            }
            HStack(spacing: 10) {
                statTile(value: String(format: "%.1f", summary.avgWet),
                         label: "Wet diapers / day", color: AppTheme.Colors.wetDiaper)
                statTile(value: String(format: "%.1f", summary.avgDirty),
                         label: "Dirty diapers / day", color: AppTheme.Colors.poopDiaper)
                if summary.hasOz && summary.hasNursing {
                    statTile(value: summary.feedGapText,
                             label: "Between feeds", color: AppTheme.Colors.primaryAction)
                }
            }
        }
        .padding(.horizontal)
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppTheme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(AppTheme.Colors.appBackground)
        .cornerRadius(AppTheme.Radius.sm)
    }

    // ── Charts (same look as InsightsView) ──────────────────────────────────

    // Value labels on every bar (7-day mode only — 30 thin bars can't fit labels,
    // there the axis + averages tiles carry the exact numbers).
    private var showsBarValues: Bool { timeframe == .week }

    private var feedingsChart: some View {
        chartSection(icon: "drop.fill", tint: AppTheme.Colors.primaryAction, title: "Feedings per Day") {
            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Feedings", day.feedings)
                )
                .foregroundStyle(AppTheme.Colors.primaryAction.gradient)
                .cornerRadius(4)
                .annotation(position: .top, alignment: .center) {
                    if showsBarValues && day.feedings > 0 {
                        Text("\(day.feedings)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.primaryAction)
                    }
                }
            }
        }
    }

    private var ozChart: some View {
        chartSection(icon: "waterbottle.fill", tint: AppTheme.Colors.bottleFeeding, title: "Bottle + Formula (oz) per Day") {
            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Oz", day.totalOz)
                )
                .foregroundStyle(AppTheme.Colors.bottleFeeding.gradient)
                .cornerRadius(4)
                .annotation(position: .top, alignment: .center) {
                    if showsBarValues && day.totalOz > 0 {
                        Text(String(format: "%.1f", day.totalOz))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.bottleFeeding)
                    }
                }
            }
        }
    }

    private var diapersChart: some View {
        chartSection(icon: "leaf.fill", tint: AppTheme.Colors.poopDiaper, title: "Diapers per Day") {
            Chart(days) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Count", day.wetDiapers)
                )
                .foregroundStyle(by: .value("Type", "Wet"))
                .cornerRadius(4)
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Count", day.dirtyDiapers)
                )
                .foregroundStyle(by: .value("Type", "Dirty"))
                .cornerRadius(4)
                .annotation(position: .top, alignment: .center) {
                    if showsBarValues && (day.wetDiapers + day.dirtyDiapers) > 0 {
                        Text("\(day.wetDiapers + day.dirtyDiapers)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppTheme.Colors.poopDiaper)
                    }
                }
            }
            .chartForegroundStyleScale([
                "Wet": AppTheme.Colors.wetDiaper,
                "Dirty": AppTheme.Colors.poopDiaper
            ])
        }
    }

    private func chartSection<C: View>(icon: String, tint: Color, title: String,
                                       @ViewBuilder chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(tint)
                Text(title)
                    .font(AppTheme.Typography.sectionHeader)
                    .foregroundColor(AppTheme.Colors.primaryText)
            }
            chart()
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let int = value.as(Int.self) {
                                Text("\(int)")
                                    .font(AppTheme.Typography.labelSmall)
                                    .foregroundColor(AppTheme.Colors.tertiaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: timeframe == .week ? 7 : 6)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(AppTheme.Typography.labelSmall)
                            .foregroundStyle(AppTheme.Colors.secondaryText)
                    }
                }
                .frame(height: 150)
        }
        .padding(.horizontal)
    }

    // ── Footer ──────────────────────────────────────────────────────────────

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "stethoscope")
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.tertiaryText)
                Text("Generated by Mommy's Log from manually entered data, which may contain errors or omissions. This is not medical advice, a diagnosis, or a medical record, and is provided for personal reference only. Always consult your pediatrician or a qualified healthcare provider about your baby's feeding, diapering, and health.")
                    .font(AppTheme.Typography.labelSmall)
                    .foregroundColor(AppTheme.Colors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        PediatricianReportView()
            .environmentObject(DataStore())
    }
}
