import SwiftUI
import OnePercentCore

/// Seven toggles, one per weekday, in the calendar's own order. Turning a day on or off yields a
/// `HabitSchedule` (folded to "Every day", "Weekdays" or "Every Friday" when it matches one).
/// At least one day always stays on, so a habit can never be scheduled for nothing.
struct WeekdayPickerView: View {
    let schedule: HabitSchedule
    let calendar: Calendar
    var onChange: (HabitSchedule) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(orderedDays, id: \.self) { day in
                WeekdayToggle(
                    label: shortName(for: day),
                    fullName: fullName(for: day),
                    isOn: schedule.selectedDays.contains(day)
                ) {
                    toggle(day)
                }
            }
        }
    }

    /// Weekday numbers starting from the calendar's first weekday (Monday in Italy).
    private var orderedDays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func toggle(_ day: Int) {
        var days = schedule.selectedDays
        if days.contains(day) {
            guard days.count > 1 else { return }
            days.remove(day)
        } else {
            days.insert(day)
        }
        onChange(.custom(days: Array(days)))
    }

    private func shortName(for day: Int) -> String {
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.indices.contains(day - 1) else { return "" }
        return String(symbols[day - 1].prefix(3)).localizedCapitalized
    }

    private func fullName(for day: Int) -> String {
        let symbols = calendar.weekdaySymbols
        return symbols.indices.contains(day - 1) ? symbols[day - 1].localizedCapitalized : ""
    }
}

private struct WeekdayToggle: View {
    let label: String
    let fullName: String
    let isOn: Bool
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isOn ? IslandPalette.streakAccent : (isHovered ? IslandPalette.secondaryText : IslandPalette.tertiaryText))
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius + 1, style: .continuous)
                        .fill(isOn ? IslandPalette.streakAccent.opacity(0.16) : (isHovered ? IslandPalette.hoverFill : IslandPalette.restFill))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.92))
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isOn)
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .help(fullName)
        .accessibilityLabel(fullName)
        .accessibilityValue(isOn ? L("On") : L("Off"))
        .accessibilityAddTraits(.isButton)
    }
}
