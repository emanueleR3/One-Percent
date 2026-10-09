import SwiftUI
import OnePercentCore

/// Big percentage, what is left, the streak and the way to stats and settings.
struct TodayHeader: View {
    let progress: TaskProgress
    let streak: Int
    let isTodayCounted: Bool
    let hasOpenTheOne: Bool
    var onStats: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(progress.percentageInt)")
                        .lineLimit(1)
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(progress.percentageInt)))
                    Text("%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.secondaryText)
                }
                .foregroundStyle(Theme.primaryText)
                .fixedSize()
                .layoutPriority(2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L("%d of %d", progress.completedCount, progress.totalCount))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                    subtitle
                }
                .lineLimit(1)

                Spacer(minLength: 4)

                Button(action: onStats) {
                    HStack(spacing: 5) {
                        Image(systemName: isTodayCounted ? "flame.fill" : "flame")
                        Text("\(streak)").monospacedDigit()
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(streak > 0 ? Theme.orange : Theme.tertiaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(streak > 0 && isTodayCounted ? Theme.orange.opacity(0.16) : Theme.surface))
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .layoutPriority(3)
                .accessibilityLabel(L("Stats"))

                IconButton(systemName: "gearshape", label: L("Settings"), action: onSettings)
            }

            ProgressBar(ratio: progress.ratio)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if progress.totalCount > 0 && progress.completedCount == progress.totalCount {
            Text(L("All done")).foregroundStyle(Theme.mint).font(.system(size: 14, weight: .medium))
        } else if hasOpenTheOne {
            Label(L("The One"), systemImage: "star.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.lavender)
        } else if progress.totalCount > 0 {
            Text(L("%d left", progress.totalCount - progress.completedCount))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        } else {
            Text(L("no goals")).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.tertiaryText)
        }
    }
}

struct ProgressBar: View {
    let ratio: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.mint)
                    .frame(width: max(ratio > 0 ? 6 : 0, geometry.size.width * ratio))
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: ratio)
        .accessibilityHidden(true)
    }
}

/// The last seven days as small rings; tap one to open that day.
struct WeekStrip: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        let calendar = store.dateService.currentCalendar
        let selected = store.dateService.normalize(store.selectedDate)

        HStack(spacing: 0) {
            ForEach(store.tracking.week) { day in
                let isSelected = store.dateService.normalize(day.date) == selected
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.selectDate(day.date) }
                } label: {
                    VStack(spacing: 5) {
                        DayRing(day: day, isSelected: isSelected)
                            .frame(width: 28, height: 28)
                        Text(letter(for: day.date, calendar: calendar))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? Theme.primaryText : Theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.dateService.formatDayTitle(for: day.date))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func letter(for date: Date, calendar: Calendar) -> String {
        let symbols = calendar.veryShortWeekdaySymbols
        let index = calendar.component(.weekday, from: date) - 1
        return symbols.indices.contains(index) ? symbols[index].uppercased() : ""
    }
}

struct DayRing: View {
    let day: DayStats
    let isSelected: Bool
    private let lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: lineWidth).opacity(day.isPerfect ? 0 : 1)
            Circle()
                .trim(from: 0, to: day.isPerfect ? 1 : CGFloat(day.ratio))
                .stroke(Theme.mint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)
                .opacity(day.isPerfect ? 0 : (day.ratio > 0 ? 1 : 0))
            Circle().fill(Theme.mint).opacity(day.isPerfect ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.78))
                .opacity(day.isPerfect ? 1 : 0)
            Circle()
                .fill(Theme.tertiaryText.opacity(0.7))
                .frame(width: 5, height: 5)
                .opacity(day.hasGoals && day.ratio == 0 && !day.isPerfect ? 1 : 0)
            Circle()
                .strokeBorder(Theme.primaryText.opacity(0.9), lineWidth: 1.2)
                .padding(-4)
                .opacity(isSelected ? 1 : 0)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: day.ratio)
    }
}

/// Previous / next day around the day's title; tapping the title returns to today.
struct DayBar: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        HStack {
            chevron("chevron.left", enabled: store.canGoToPreviousDay, label: L("Previous day")) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.selectPreviousDay() }
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.selectToday() }
            } label: {
                Text(store.dateService.formatDayTitle(for: store.selectedDate))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(store.dateService.isToday(store.selectedDate) ? Theme.primaryText : Theme.lavender)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(Theme.surface))
            }
            .buttonStyle(.plain)
            Spacer()
            chevron("chevron.right", enabled: store.canGoToNextDay, label: L("Next day")) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.selectNextDay() }
            }
        }
    }

    private func chevron(_ name: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? Theme.secondaryText : Theme.tertiaryText.opacity(0.35))
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
