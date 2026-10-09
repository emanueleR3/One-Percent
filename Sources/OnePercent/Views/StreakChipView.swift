import SwiftUI

/// Flame + day count. A filled flame means today is already banked; an outline means one more
/// goal keeps the streak going. The flame bounces whenever the count goes up.
struct StreakChipView: View {
    let streak: Int
    let best: Int
    let isTodayCounted: Bool
    var action: () -> Void

    @State private var isHovered = false

    private var isLit: Bool { streak > 0 && isTodayCounted }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isTodayCounted ? "flame.fill" : "flame")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(flameColor)
                    .symbolEffect(.bounce, value: streak)

                Text("\(streak)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(streak)))
                    .foregroundStyle(streak > 0 ? IslandPalette.primaryText : IslandPalette.tertiaryText)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                    .fill(isLit ? IslandPalette.streakAccent.opacity(isHovered ? 0.22 : 0.14) : (isHovered ? IslandPalette.hoverFill : IslandPalette.restFill))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.94))
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .animation(.snappy(duration: 0.35), value: streak)
        .animation(IslandAnimations.hoverFade, value: isLit)
        .help(helpText)
        .accessibilityLabel("Streak: \(streak) \(streak == 1 ? "day" : "days"). Best: \(best). \(isTodayCounted ? "Today is counted." : "Complete a goal today to keep it.")")
    }

    private var flameColor: Color {
        if isLit { return IslandPalette.streakAccent }
        return streak > 0 ? IslandPalette.streakAccent.opacity(0.6) : IslandPalette.tertiaryText
    }

    private var helpText: String {
        let days = streak == 1 ? "1-day streak" : "\(streak)-day streak"
        let record = best > 0 ? " · best \(best)" : ""
        if streak == 0 { return "No streak yet. Complete a goal today to start one." }
        return isTodayCounted ? "\(days)\(record)" : "\(days)\(record). Complete a goal today to keep it."
    }
}
