import SwiftUI

/// Single-choice chips in a row (open delay, side of the notch...).
struct OptionChips<Value: Hashable>: View {
    struct Option: Identifiable {
        let label: String
        let value: Value
        var id: String { label }
    }

    let options: [Option]
    @Binding var selection: Value
    var accessibility: String = L("Option")

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                OptionChip(label: option.label, isOn: option.value == selection) {
                    selection = option.value
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibility)
    }
}

private struct OptionChip: View {
    let label: String
    let isOn: Bool
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isOn ? IslandPalette.completedAccent : (isHovered ? IslandPalette.secondaryText : IslandPalette.tertiaryText))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius + 1, style: .continuous)
                        .fill(isOn ? IslandPalette.completedAccent.opacity(0.14) : (isHovered ? IslandPalette.hoverFill : IslandPalette.restFill))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.94))
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isOn)
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// `- 25 min +` for whole-number settings.
struct MinuteStepperView: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 5
    var unit: String = "min"

    var body: some View {
        HStack(spacing: 2) {
            StepperButton(systemName: "minus") { value = max(range.lowerBound, value - step) }
                .disabled(value <= range.lowerBound)

            Text(unit.isEmpty ? "\(value)" : "\(value) \(unit)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(IslandPalette.primaryText)
                .contentTransition(.numericText(value: Double(value)))
                .frame(minWidth: 52)
                .animation(.snappy(duration: 0.2), value: value)

            StepperButton(systemName: "plus") { value = min(range.upperBound, value + step) }
                .disabled(value >= range.upperBound)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(value) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

/// `- 264 pt +` for a size that is automatic until the user changes it. Stepping back onto the
/// automatic value makes it automatic again, and the arrow returns to it at once.
struct SizeStepperView: View {
    /// Stored value; 0 means automatic.
    @Binding var value: Double
    let automatic: Double
    let range: ClosedRange<Double>
    var step: Double = 2
    let accessibility: String

    private var effective: Double { value > 0 ? value : automatic }

    private func move(by delta: Double) {
        let next = min(range.upperBound, max(range.lowerBound, effective + delta))
        value = abs(next - automatic) < 0.5 ? 0 : next
    }

    var body: some View {
        HStack(spacing: 2) {
            StepperButton(systemName: "minus") { move(by: -step) }
                .disabled(effective <= range.lowerBound)

            Text("\(Int(effective.rounded())) pt")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(value > 0 ? IslandPalette.primaryText : IslandPalette.secondaryText)
                .contentTransition(.numericText(value: effective))
                .frame(minWidth: 52)
                .animation(.snappy(duration: 0.2), value: effective)

            StepperButton(systemName: "plus") { move(by: step) }
                .disabled(effective >= range.upperBound)

            StepperButton(systemName: "arrow.counterclockwise") { value = 0 }
                .opacity(value > 0 ? 1 : 0)
                .disabled(value == 0)
                .accessibilityLabel(L("Reset size"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibility)
        .accessibilityValue("\(Int(effective.rounded())) pt")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: step)
            case .decrement: move(by: -step)
            @unknown default: break
            }
        }
    }
}

private struct StepperButton: View {
    let systemName: String
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(isHovered && isEnabled ? IslandPalette.primaryText : IslandPalette.secondaryText)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .fill(isHovered && isEnabled ? IslandPalette.hoverFill : IslandPalette.restFill)
                )
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
    }
}
