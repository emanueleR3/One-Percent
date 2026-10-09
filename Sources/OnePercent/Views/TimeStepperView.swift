import SwiftUI

/// `- 21:00 +` in 15 minute steps. Native date pickers clash with the panel, and this is faster.
struct TimeStepperView: View {
    @Binding var minutes: Int
    var isEnabled: Bool = true
    var step: Int = 15

    var body: some View {
        HStack(spacing: 2) {
            stepButton(systemName: "minus", delta: -step)

            Text(ReminderPlanner.clockString(minutes: minutes))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isEnabled ? IslandPalette.primaryText : IslandPalette.tertiaryText)
                .contentTransition(.numericText(value: Double(minutes)))
                .frame(width: 44)
                .animation(.snappy(duration: 0.2), value: minutes)

            stepButton(systemName: "plus", delta: step)
        }
        .opacity(isEnabled ? 1 : 0.55)
        .allowsHitTesting(isEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Time"))
        .accessibilityValue(ReminderPlanner.clockString(minutes: minutes))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: minutes = ReminderPlanner.clampMinutes(minutes + step)
            case .decrement: minutes = ReminderPlanner.clampMinutes(minutes - step)
            @unknown default: break
            }
        }
    }

    private func stepButton(systemName: String, delta: Int) -> some View {
        StepButton(systemName: systemName) {
            // Wrap around midnight instead of sticking at the ends.
            let day = 24 * 60
            minutes = ReminderPlanner.clampMinutes(((minutes + delta) % day + day) % day)
        }
    }
}

private struct StepButton: View {
    let systemName: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(isHovered ? IslandPalette.primaryText : IslandPalette.secondaryText)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .fill(isHovered ? IslandPalette.hoverFill : IslandPalette.restFill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
    }
}
