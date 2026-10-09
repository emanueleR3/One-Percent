import SwiftUI
import OnePercentCore

/// Sizes both stats tabs share, so switching between them never moves the footer or resizes the page.
enum StatsLayout {
    /// Room for an eyebrow, a number and a one-line caption.
    static let tileRowHeight: CGFloat = 66
    /// The block under the tiles (heatmap + score, or day bars + top goals, or the empty state).
    static let detailHeight: CGFloat = 112
}

/// Second page of the panel: streak, completion rates, 12-week heatmap and the 1% score.
struct StatsView: View {
    enum Tab: Hashable {
        case overview
        case focus
    }

    @ObservedObject var store: TaskStore
    var onSelectDay: (Date) -> Void

    @State private var tab: Tab

    init(store: TaskStore, onSelectDay: @escaping (Date) -> Void, initialTab: Tab = .overview) {
        self.store = store
        self.onSelectDay = onSelectDay
        self._tab = State(initialValue: initialTab)
    }

    var body: some View {
        let summary = store.tracking

        VStack(alignment: .leading, spacing: 10) {
            switch tab {
            case .overview:
                StatTilesRow(summary: summary)

                HStack(alignment: .top, spacing: 12) {
                    HeatmapView(
                        summary: summary,
                        calendar: store.dateService.currentCalendar,
                        today: store.dateService.today,
                        canOpen: { store.dateService.daysFromToday(to: $0) >= -7 && store.dateService.daysFromToday(to: $0) <= 7 },
                        onSelect: onSelectDay
                    )

                    ScoreCardView(score: summary.score, curve: summary.scoreCurve, perfectDays: summary.perfectDays)
                }
                .frame(height: StatsLayout.detailHeight)
            case .focus:
                FocusStatsView(store: store)
            }

            footer(summary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(IslandAnimations.hoverFade, value: tab)
    }

    private func footer(_ summary: TrackingSummary) -> some View {
        HStack(spacing: 6) {
            if tab == .overview {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(IslandPalette.tertiaryText)

                Text(bestDayText(summary))
                    .font(IslandTypography.secondaryMetadata)
                    .foregroundStyle(IslandPalette.secondaryText)
                    .lineLimit(1)
            } else {
                Image(systemName: "timer")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(IslandPalette.tertiaryText)

                Text(L("Time is kept when you pause or finish"))
                    .font(IslandTypography.secondaryMetadata)
                    .foregroundStyle(IslandPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            OptionChips(
                options: [.init(label: L("Overview"), value: Tab.overview), .init(label: L("Focus"), value: Tab.focus)],
                selection: $tab,
                accessibility: L("Stats page")
            )
        }
        .frame(height: 24)
        .padding(.horizontal, 2)
    }

    private func bestDayText(_ summary: TrackingSummary) -> String {
        guard let best = summary.bestWeekday else {
            return L("Best weekday shows up after two of each")
        }
        let calendar = store.dateService.currentCalendar
        let symbols = calendar.weekdaySymbols
        let index = best.weekday - 1
        let name = symbols.indices.contains(index) ? symbols[index].localizedCapitalized : "—"
        return L("Best day: %@ · %d%% done", name, Int((best.averageRatio * 100).rounded()))
    }
}

// MARK: - Tiles

private struct StatTilesRow: View {
    let summary: TrackingSummary

    var body: some View {
        HStack(spacing: 0) {
            StatTile(
                title: L("Streak"),
                value: Double(summary.currentStreak),
                format: { "\(Int($0.rounded()))" },
                unit: summary.currentStreak == 1 ? L("day") : L("days"),
                caption: L("best %d", summary.bestStreak),
                tint: summary.isTodayCounted && summary.currentStreak > 0 ? IslandPalette.streakAccent : IslandPalette.primaryText
            )
            divider
            StatTile(
                title: L("7 days"),
                value: (summary.rate7 ?? 0) * 100,
                format: { "\(Int($0.rounded()))" },
                unit: "%",
                caption: summary.rate7 == nil ? L("no goals") : L("goals done"),
                tint: IslandPalette.primaryText
            )
            divider
            StatTile(
                title: L("30 days"),
                value: (summary.rate30 ?? 0) * 100,
                format: { "\(Int($0.rounded()))" },
                unit: "%",
                caption: summary.rate30 == nil ? L("no goals") : L("goals done"),
                tint: IslandPalette.primaryText
            )
            divider
            StatTile(
                title: L("Per day"),
                value: summary.averagePerDay,
                format: { String(format: "%.1f", $0) },
                unit: "",
                caption: L("goals done"),
                tint: IslandPalette.primaryText
            )
        }
        .frame(height: StatsLayout.tileRowHeight)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(IslandPalette.restFill)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(IslandPalette.hairline)
            .frame(width: 1, height: 30)
    }
}

private struct StatTile: View {
    let title: String
    let value: Double
    let format: (Double) -> String
    let unit: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EyebrowText(title)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                RollingNumberText(value: value, format: format)
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .lineLimit(1)
                }
            }

            Text(caption)
                .font(IslandTypography.statCaption)
                .foregroundStyle(IslandPalette.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(format(value)) \(unit), \(caption)")
    }
}

// MARK: - Heatmap

/// 12 weeks x 7 days. Brighter mint = more of the day's goals done; solid = perfect day.
private struct HeatmapView: View {
    let summary: TrackingSummary
    let calendar: Calendar
    let today: Date
    let canOpen: (Date) -> Bool
    let onSelect: (Date) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowText(L("Last 12 weeks"))

            HStack(alignment: .top, spacing: 5) {
                weekdayLabels

                HStack(spacing: gap) {
                    ForEach(Array(summary.heatmap.enumerated()), id: \.offset) { column, days in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                cellView(days.indices.contains(row) ? days[row] : nil, column: column, row: row)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                // One frame later so the cells animate in from their hidden state.
                DispatchQueue.main.async { appeared = true }
            }
        }
    }

    /// M / W / F (or the locale's equivalents) down the left edge.
    private var weekdayLabels: some View {
        VStack(alignment: .trailing, spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                Text(row % 2 == 0 ? label(forRow: row) : "")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(IslandPalette.tertiaryText)
                    .frame(height: cell)
            }
        }
        .accessibilityHidden(true)
    }

    private func label(forRow row: Int) -> String {
        let weekdayIndex = (calendar.firstWeekday - 1 + row) % 7
        let symbols = calendar.veryShortWeekdaySymbols
        return symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex].uppercased() : ""
    }

    @ViewBuilder
    private func cellView(_ day: DayStats?, column: Int, row: Int) -> some View {
        if let day {
            HeatCell(calendar: calendar, day: day, isToday: calendar.isDate(day.date, inSameDayAs: today), size: cell, enabled: canOpen(day.date)) {
                onSelect(day.date)
            }
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.6)
            .animation(
                reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8).delay(Double(column) * 0.02 + Double(row) * 0.004),
                value: appeared
            )
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }
}

private struct HeatCell: View {
    let calendar: Calendar
    let day: DayStats
    let isToday: Bool
    let size: CGFloat
    let enabled: Bool
    var action: () -> Void

    @State private var isHovered = false

    private func tooltipDate(_ date: Date) -> String {
        LocalizedDates.string(date, template: "EEEMMMd", calendar: calendar)
    }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(fill)
                .frame(width: size, height: size)
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(IslandPalette.primaryText.opacity(0.75), lineWidth: 1)
                    }
                }
                .scaleEffect(isHovered && enabled ? 1.18 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .help("\(tooltipDate(day.date)) · \(summary)")
        .accessibilityLabel("\(tooltipDate(day.date)), \(summary)")
    }

    private var summary: String {
        if !day.hasGoals { return L("no goals") }
        if day.total == 0 { return L("moved to tomorrow") }
        return L("%d of %d done", day.completed, day.total)
    }

    private var fill: Color {
        if !day.hasGoals { return Color.white.opacity(0.05) }
        if day.total == 0 { return IslandPalette.deferredAccent.opacity(0.22) }
        if day.completed == 0 { return Color.white.opacity(0.11) }
        if day.isPerfect { return IslandPalette.completedAccent }
        return IslandPalette.completedAccent.opacity(0.28 + 0.42 * day.ratio)
    }
}

// MARK: - 1% score

private struct ScoreCardView: View {
    let score: Double
    let curve: [Double]
    let perfectDays: Int

    @State private var reveal: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var gainPercent: Double { (score - 1) * 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                EyebrowText(L("1% score"))
                Spacer(minLength: 4)
                Text(Lp("%d perfect day", "%d perfect days", perfectDays))
                    .font(IslandTypography.statCaption)
                    .foregroundStyle(IslandPalette.tertiaryText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                RollingNumberText(value: score, format: { String(format: "%.2f", $0) }, font: IslandTypography.statValueLarge)
                    .foregroundStyle(perfectDays > 0 ? IslandPalette.completedAccent : IslandPalette.primaryText)
                Text("×")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandPalette.tertiaryText)
                    .offset(x: -3)

                Spacer(minLength: 4)

                Text(String(format: "+%.1f%%", gainPercent))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(perfectDays > 0 ? IslandPalette.completedAccent.opacity(0.85) : IslandPalette.tertiaryText)
            }

            ScoreCurve(values: curve, reveal: reveal)
                .frame(maxHeight: .infinity)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(IslandPalette.restFill)
        )
        .onAppear {
            if reduceMotion {
                reveal = 1
            } else {
                withAnimation(.easeOut(duration: 0.9).delay(0.15)) { reveal = 1 }
            }
        }
        .help(L("Every day you close at 100% multiplies your score by 1.01."))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("1 percent score %@ times, %d perfect days", String(format: "%.2f", score), perfectDays))
    }
}

/// Sparkline of the cumulative score. Flat (dim) until the first perfect day.
private struct ScoreCurve: View {
    let values: [Double]
    var reveal: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let points = Self.points(for: values, in: geometry.size)
            let isFlat = (values.max() ?? 1) - (values.min() ?? 1) < 0.0000001

            ZStack {
                if points.count > 1 {
                    // Area
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geometry.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [IslandPalette.completedAccent.opacity(isFlat ? 0 : 0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask(alignment: .leading) {
                        Rectangle().scaleEffect(x: reveal, anchor: .leading)
                    }

                    // Line
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .trim(from: 0, to: reveal)
                    .stroke(
                        isFlat ? IslandPalette.tertiaryText.opacity(0.5) : IslandPalette.completedAccent,
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
                    )

                    // Head
                    if let last = points.last {
                        Circle()
                            .fill(isFlat ? IslandPalette.tertiaryText : IslandPalette.completedAccent)
                            .frame(width: 5, height: 5)
                            .shadow(color: IslandPalette.completedAccent.opacity(isFlat ? 0 : 0.6), radius: 4)
                            .position(last)
                            .opacity(reveal >= 1 ? 1 : 0)
                            .animation(.easeOut(duration: 0.2), value: reveal)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static func points(for values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count > 1, size.width > 0, size.height > 0 else { return [] }
        let low = values.min() ?? 1
        let high = values.max() ?? 1
        let span = max(high - low, 0.0000001)
        let inset: CGFloat = 4
        let usableHeight = max(1, size.height - inset * 2)
        let flat = high - low < 0.0000001
        return values.enumerated().map { index, value in
            let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
            let normalized = flat ? 0 : (value - low) / span
            let y = size.height - inset - CGFloat(normalized) * usableHeight
            return CGPoint(x: x, y: y)
        }
    }
}
