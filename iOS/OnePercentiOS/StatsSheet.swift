import SwiftUI
import OnePercentCore

/// Streak, completion rates, the score curve and the last twelve weeks, plus where the time went.
struct StatsSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    private enum Tab: Hashable { case overview, focus }
    @State private var tab: Tab = .overview

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        ChoiceChip(title: L("Overview"), isSelected: tab == .overview) { withAnimation(.snappy) { tab = .overview } }
                        ChoiceChip(title: L("Focus"), isSelected: tab == .focus) { withAnimation(.snappy) { tab = .focus } }
                    }

                    if tab == .overview {
                        overview(store.tracking)
                    } else {
                        FocusStatsContent(store: store)
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(L("Stats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() }.foregroundStyle(Theme.mint) }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
    }

    // MARK: Overview

    @ViewBuilder
    private func overview(_ summary: TrackingSummary) -> some View {
        StatRow(tiles: [
            .init(title: L("Streak"), value: "\(summary.currentStreak)", caption: L("best %d", summary.bestStreak), tint: Theme.orange),
            .init(title: L("7 days"), value: percent(summary.rate7), caption: summary.rate7 == nil ? L("no goals") : L("goals done"), tint: Theme.mint),
            .init(title: L("30 days"), value: percent(summary.rate30), caption: summary.rate30 == nil ? L("no goals") : L("goals done"), tint: Theme.mint),
            .init(title: L("Per day"), value: String(format: "%.1f", summary.averagePerDay), caption: L("goals done"), tint: Theme.primaryText)
        ])

        // The twelve weeks come first: it is the picture people open this page for.
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Last 12 weeks").uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Theme.tertiaryText)
            Heatmap(columns: summary.heatmap)
        }

        ScoreCard(score: summary.score, curve: summary.scoreCurve, perfectDays: summary.perfectDays)
    }

    private func percent(_ rate: Double?) -> String {
        rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
    }
}

/// A few numbers in one slim card: label, value, caption, with hairlines between them.
struct StatRow: View {
    struct Tile: Identifiable {
        let id = UUID()
        let title: String
        let value: String
        let caption: String
        let tint: Color
    }

    let tiles: [Tile]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 34)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.6)
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(tile.value)
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(tile.tint)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(tile.caption)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            }
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}

// MARK: - 1% score

/// The score (1.01 for every perfect day) and its curve over the last weeks.
private struct ScoreCard: View {
    let score: Double
    let curve: [Double]
    let perfectDays: Int

    @State private var reveal: CGFloat = 0

    private var gainPercent: Double { (score - 1) * 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("1% score").uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Theme.tertiaryText)
                Spacer()
                Text(Lp("%d perfect day", "%d perfect days", perfectDays))
                    .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Theme.secondaryText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", score))
                    .font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(perfectDays > 0 ? Theme.mint : Theme.primaryText)
                Text("×").font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(Theme.tertiaryText)
                Spacer()
                Text(String(format: "+%.1f%%", gainPercent))
                    .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(perfectDays > 0 ? Theme.mint.opacity(0.85) : Theme.tertiaryText)
            }

            ScoreCurve(values: curve, reveal: reveal)
                .frame(height: 96)
                .padding(.top, 2)

            Text(L("Every day you close at 100% multiplies your score by 1.01."))
                .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.tertiaryText)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.15)) { reveal = 1 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("1 percent score %@ times, %d perfect days", String(format: "%.2f", score), perfectDays))
    }
}

/// Sparkline of the cumulative score. Flat (and dim) until the first perfect day.
private struct ScoreCurve: View {
    let values: [Double]
    var reveal: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let points = Self.points(for: values, in: geometry.size)
            let isFlat = (values.max() ?? 1) - (values.min() ?? 1) < 0.0000001

            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: geometry.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Theme.mint.opacity(isFlat ? 0 : 0.22), .clear], startPoint: .top, endPoint: .bottom))
                    .mask(alignment: .leading) { Rectangle().scaleEffect(x: reveal, anchor: .leading) }

                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .trim(from: 0, to: reveal)
                    .stroke(
                        isFlat ? Theme.tertiaryText.opacity(0.5) : Theme.mint,
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )

                    if let last = points.last {
                        Circle()
                            .fill(isFlat ? Theme.tertiaryText : Theme.mint)
                            .frame(width: 8, height: 8)
                            .shadow(color: Theme.mint.opacity(isFlat ? 0 : 0.6), radius: 5)
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
        let inset: CGFloat = 6
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

// MARK: - Heatmap

private struct Heatmap: View {
    let columns: [[DayStats?]]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(columns.indices, id: \.self) { column in
                VStack(spacing: 4) {
                    ForEach(columns[column].indices, id: \.self) { row in
                        cell(columns[column][row])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cell(_ day: DayStats?) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color(for: day))
            .aspectRatio(1, contentMode: .fit)
    }

    private func color(for day: DayStats?) -> Color {
        guard let day else { return Color.clear }
        if day.isPerfect { return Theme.mint }
        if day.ratio > 0 { return Theme.mint.opacity(0.25 + 0.5 * day.ratio) }
        return Theme.surface
    }
}

// MARK: - Focus

/// The time tracked today and this week, per day, and per goal.
private struct FocusStatsContent: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        let calendar = store.dateService.currentCalendar
        let summary = FocusCalculator.summary(tasks: store.allTasks, now: Date(), calendar: calendar)
        let isEmpty = summary.weekSeconds == 0 && summary.days.allSatisfy { $0.seconds == 0 }

        VStack(alignment: .leading, spacing: 22) {
            StatRow(tiles: [
                .init(title: L("Today"), value: FocusFormat.compact(summary.todaySeconds), caption: L("tracked"), tint: Theme.amber),
                .init(title: L("7 days"), value: FocusFormat.compact(summary.weekSeconds),
                      caption: Lp("%d session", "%d sessions", summary.sessionCount), tint: Theme.primaryText),
                .init(title: L("Per goal"), value: summary.averagePerGoal.map(FocusFormat.compact) ?? "–", caption: L("on average"), tint: Theme.primaryText)
            ])

            if isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "timer").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                    Text(L("No time tracked yet")).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Theme.primaryText)
                    Text(L("Press play on a goal to time it, or turn on Pomodoro in Settings."))
                        .font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.tertiaryText).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            } else {
                DayBars(days: summary.days, calendar: calendar)
                TopGoals(goals: summary.topGoals)
            }
        }
    }
}

private struct DayBars: View {
    let days: [FocusDay]
    let calendar: Calendar
    @State private var appeared = false

    private let barArea: CGFloat = 110

    var body: some View {
        let maxSeconds = max(days.map(\.seconds).max() ?? 0, 60)

        VStack(alignment: .leading, spacing: 12) {
            Text(L("Last 7 days").uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Theme.tertiaryText)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let isToday = index == days.count - 1
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.05)).frame(height: barArea)
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isToday ? Theme.amber : Theme.amber.opacity(0.45))
                                .frame(height: max(day.seconds > 0 ? 5 : 0, barArea * CGFloat(day.seconds / maxSeconds)) * (appeared ? 1 : 0.0001), alignment: .bottom)
                                .animation(.spring(response: 0.45, dampingFraction: 0.82).delay(Double(index) * 0.03), value: appeared)
                        }
                        .frame(height: barArea)
                        Text(letter(for: day.date))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isToday ? Theme.primaryText : Theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(LocalizedDates.string(day.date, template: "EEEMMMd", calendar: calendar)), \(FocusFormat.compact(day.seconds))")
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .onAppear { DispatchQueue.main.async { appeared = true } }
    }

    private func letter(for date: Date) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        let symbols = calendar.veryShortWeekdaySymbols
        return symbols.indices.contains(index) ? symbols[index].uppercased() : ""
    }
}

private struct TopGoals: View {
    let goals: [FocusGoalTime]

    var body: some View {
        let longest = max(goals.first?.seconds ?? 0, 1)

        VStack(alignment: .leading, spacing: 14) {
            Text(L("Where it went").uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded)).tracking(0.8).foregroundStyle(Theme.tertiaryText)

            if goals.isEmpty {
                Text(L("Nothing yet")).font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.tertiaryText)
            } else {
                ForEach(goals.prefix(5)) { goal in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(goal.title).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(Theme.primaryText).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(FocusFormat.compact(goal.seconds)).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                        }
                        GeometryReader { geometry in
                            Capsule().fill(Theme.amber.opacity(0.55)).frame(width: max(4, geometry.size.width * CGFloat(goal.seconds / longest)))
                        }
                        .frame(height: 4)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }
}
