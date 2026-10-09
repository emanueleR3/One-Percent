import SwiftUI
import OnePercentCore

/// The last seven days as mini progress rings. Tap one to open that day.
struct WeekStripView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        let calendar = store.dateService.currentCalendar
        let selected = store.dateService.normalize(store.selectedDate)

        HStack(spacing: 2) {
            ForEach(store.tracking.week) { day in
                WeekDayCell(
                    day: day,
                    letter: Self.letter(for: day.date, calendar: calendar),
                    isSelected: day.date == selected,
                    isToday: store.dateService.isToday(day.date),
                    accessibilityTitle: store.dateService.formatDayTitle(for: day.date)
                ) {
                    withAnimation(IslandAnimations.statusTransition) {
                        store.selectDate(day.date)
                    }
                }
            }
        }
    }

    private static func letter(for date: Date, calendar: Calendar) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        let symbols = calendar.veryShortWeekdaySymbols
        return symbols.indices.contains(index) ? symbols[index].uppercased() : ""
    }
}

private struct WeekDayCell: View {
    let day: DayStats
    let letter: String
    let isSelected: Bool
    let isToday: Bool
    let accessibilityTitle: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                DayRing(day: day, isSelected: isSelected, isHovered: isHovered)
                    .frame(width: 18, height: 18)

                Text(letter)
                    .font(IslandTypography.weekdayLetter)
                    .foregroundStyle(letterColor)
            }
            .frame(width: 26, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.9))
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .animation(IslandAnimations.hoverFade, value: isSelected)
        .help(helpText)
        .accessibilityLabel("\(accessibilityTitle), \(summary)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var letterColor: Color {
        if isSelected { return IslandPalette.primaryText }
        return isToday ? IslandPalette.secondaryText : IslandPalette.tertiaryText
    }

    private var summary: String {
        if !day.hasGoals { return L("no goals") }
        if day.total == 0 { return L("all moved to tomorrow") }
        return L("%d of %d done", day.completed, day.total)
    }

    private var helpText: String {
        "\(accessibilityTitle) · \(summary)"
    }
}

/// Ring that fills with the day's completion; a perfect day becomes a solid disc with a check.
private struct DayRing: View {
    let day: DayStats
    let isSelected: Bool
    let isHovered: Bool

    private let lineWidth: CGFloat = 2.2

    var body: some View {
        ZStack {
            // Track
            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: lineWidth)
                .opacity(day.isPerfect ? 0 : 1)

            // Progress arc
            Circle()
                .trim(from: 0, to: day.isPerfect ? 1 : CGFloat(day.ratio))
                .stroke(IslandPalette.completedAccent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)
                .opacity(day.isPerfect ? 0 : (day.ratio > 0 ? 1 : 0))

            // Perfect day
            Circle()
                .fill(IslandPalette.completedAccent)
                .scaleEffect(day.isPerfect ? 1 : 0.5)
                .opacity(day.isPerfect ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.78))
                .scaleEffect(day.isPerfect ? 1 : 0.4)
                .opacity(day.isPerfect ? 1 : 0)

            // Planned but nothing done yet: a faint core so the day reads as "has goals"
            Circle()
                .fill(IslandPalette.tertiaryText.opacity(0.7))
                .frame(width: 3.5, height: 3.5)
                .opacity(day.hasGoals && day.ratio == 0 && !day.isPerfect ? 1 : 0)

            // Selection halo
            Circle()
                .strokeBorder(IslandPalette.primaryText.opacity(0.85), lineWidth: 1)
                .padding(-3)
                .opacity(isSelected ? 1 : 0)
        }
        .scaleEffect(isHovered && !isSelected ? 1.08 : 1)
        .animation(IslandAnimations.progressSpring, value: day.ratio)
        .animation(IslandAnimations.checkSpring, value: day.isPerfect)
    }
}
