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
