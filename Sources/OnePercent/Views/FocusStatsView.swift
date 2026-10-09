import SwiftUI

/// The "Focus" tab of the stats page: time tracked today and this week, per day, and per goal.
struct FocusStatsView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        let summary = FocusCalculator.summary(
            tasks: store.allTasks,
            now: Date(),
            calendar: store.dateService.currentCalendar
        )

        VStack(alignment: .leading, spacing: 10) {
            tiles(summary)

            if summary.weekSeconds == 0 && summary.days.allSatisfy({ $0.seconds == 0 }) {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 12) {
                    DayBarsView(days: summary.days, calendar: store.dateService.currentCalendar)
                    TopGoalsView(goals: summary.topGoals)
                }
                .frame(height: StatsLayout.detailHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func tiles(_ summary: FocusSummary) -> some View {
        HStack(spacing: 0) {
            FocusTile(title: L("Today"), value: FocusFormat.compact(summary.todaySeconds), caption: L("tracked"))
            divider
            FocusTile(
                title: L("7 days"),
                value: FocusFormat.compact(summary.weekSeconds),
                caption: Lp("%d session", "%d sessions", summary.sessionCount)
            )
            divider
            FocusTile(
                title: L("Per goal"),
                value: summary.averagePerGoal.map(FocusFormat.compact) ?? "–",
                caption: L("on average")
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(IslandPalette.tertiaryText)
            Text(L("No time tracked yet"))
                .font(IslandTypography.sectionTitle)
                .foregroundStyle(IslandPalette.primaryText)
            Text(L("Press play on a goal to time it, or turn on Pomodoro in Settings."))
                .font(IslandTypography.secondaryMetadata)
                .foregroundStyle(IslandPalette.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: StatsLayout.detailHeight)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(IslandPalette.restFill)
        )
    }
}

private struct FocusTile: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EyebrowText(title)
            Text(value)
                .font(IslandTypography.statValue)
                .monospacedDigit()
                .foregroundStyle(IslandPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(IslandTypography.statCaption)
                .foregroundStyle(IslandPalette.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value), \(caption)")
    }
}

/// Seven bars, one per day, ending today.
private struct DayBarsView: View {
    let days: [FocusDay]
    let calendar: Calendar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let barArea: CGFloat = 54

    var body: some View {
        let maxSeconds = max(days.map(\.seconds).max() ?? 0, 60)

        VStack(alignment: .leading, spacing: 6) {
            EyebrowText(L("Last 7 days"))

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    let isToday = index == days.count - 1
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .frame(height: barArea)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(isToday ? IslandPalette.inProgressAccent : IslandPalette.inProgressAccent.opacity(0.45))
                                .frame(height: max(day.seconds > 0 ? 3 : 0, barArea * CGFloat(day.seconds / maxSeconds)) * (appeared ? 1 : 0.0001), alignment: .bottom)
                                .animation(
                                    reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82).delay(Double(index) * 0.03),
                                    value: appeared
                                )
                        }
                        .frame(height: barArea)

                        Text(letter(for: day.date))
                            .font(IslandTypography.weekdayLetter)
                            .foregroundStyle(isToday ? IslandPalette.primaryText : IslandPalette.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(dayString(day.date)) · \(FocusFormat.compact(day.seconds))")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(dayString(day.date)), \(FocusFormat.compact(day.seconds))")
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(IslandPalette.restFill)
        )
        .onAppear {
            if reduceMotion { appeared = true } else { DispatchQueue.main.async { appeared = true } }
        }
    }

    private func dayString(_ date: Date) -> String {
        LocalizedDates.string(date, template: "EEEMMMd", calendar: calendar)
    }

    private func letter(for date: Date) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        let symbols = calendar.veryShortWeekdaySymbols
        return symbols.indices.contains(index) ? symbols[index].uppercased() : ""
    }
}

/// The goals this week's time went to, longest first.
private struct TopGoalsView: View {
    let goals: [FocusGoalTime]

    var body: some View {
        let longest = max(goals.first?.seconds ?? 0, 1)

        VStack(alignment: .leading, spacing: 7) {
            EyebrowText(L("Where it went"))

            if goals.isEmpty {
                Text(L("Nothing yet"))
                    .font(IslandTypography.secondaryMetadata)
                    .foregroundStyle(IslandPalette.tertiaryText)
            } else {
                ForEach(goals.prefix(3)) { goal in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(goal.title)
                                .font(IslandTypography.statusLabel)
                                .foregroundStyle(IslandPalette.primaryText)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(FocusFormat.compact(goal.seconds))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(IslandPalette.secondaryText)
                        }
                        GeometryReader { geometry in
                            Capsule()
                                .fill(IslandPalette.inProgressAccent.opacity(0.55))
                                .frame(width: max(3, geometry.size.width * CGFloat(goal.seconds / longest)))
                        }
                        .frame(height: 3)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(width: 196, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(IslandPalette.restFill)
        )
    }
}
