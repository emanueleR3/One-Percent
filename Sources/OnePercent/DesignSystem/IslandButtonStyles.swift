import SwiftUI

/// Every pressable control shrinks a touch under the pointer so the UI visibly "hears" the click.
struct PressScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(IslandAnimations.pressFade, value: configuration.isPressed)
    }
}

/// Physical-key rendering for shortcuts, e.g. `⌘N` or `↵`.
struct KeycapView: View {
    let label: String
    var isActive: Bool = false

    var body: some View {
        Text(label)
            .font(IslandTypography.keycap)
            .foregroundStyle(isActive ? IslandPalette.completedAccent : IslandPalette.tertiaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? IslandPalette.completedAccent.opacity(0.10) : IslandPalette.restFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(isActive ? IslandPalette.completedAccent.opacity(0.35) : IslandPalette.hairline, lineWidth: 0.5)
            )
            .animation(IslandAnimations.hoverFade, value: isActive)
            .accessibilityHidden(true)
    }
}

/// Small uppercase caption used above stats: "STREAK", "1% SCORE", ...
struct EyebrowText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(IslandTypography.eyebrow)
            .tracking(0.6)
            .foregroundStyle(IslandPalette.tertiaryText)
    }
}

/// Number that rolls its digits when the value changes, and counts up from zero when first shown.
struct RollingNumberText: View {
    let value: Double
    let format: (Double) -> String
    var font: Font = IslandTypography.statValue

    @State private var shown: Double = 0

    var body: some View {
        Text(format(shown))
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText(value: shown))
            .onAppear {
                withAnimation(.snappy(duration: 0.7)) { shown = value }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.snappy(duration: 0.45)) { shown = newValue }
            }
    }
}


/// Mint on/off switch. The native one renders grey whenever the panel is not the active window,
/// which is most of the time for a notch panel, so this draws its own state.
struct IslandSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            IslandHaptics.tick()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? IslandPalette.completedAccent : Color.white.opacity(0.16))
                Circle()
                    .fill(isOn ? Color.black.opacity(0.82) : IslandPalette.primaryText)
                    .frame(width: 14, height: 14)
                    .padding(2)
            }
            .frame(width: 32, height: 18)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.94))
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isOn)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
