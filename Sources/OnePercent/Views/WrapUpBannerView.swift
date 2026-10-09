import SwiftUI

/// End-of-day prompt: "3 goals left, move them to tomorrow?", then a short Undo window.
struct WrapUpBannerView: View {
    enum Mode: Equatable {
        case prompt(goals: Int)
        case moved(goals: Int)
    }

    let mode: Mode
    var onMove: () -> Void
    var onDismiss: () -> Void
    var onUndo: () -> Void

    @State private var isActionHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(IslandPalette.deferredAccent)
                .frame(width: 16)

            message

            Spacer(minLength: 6)

            switch mode {
            case .prompt:
                actionButton(L("Move all"), action: onMove)
                dismissButton
            case .moved:
                actionButton(L("Undo"), action: onUndo)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(IslandPalette.deferredAccent.opacity(0.10))
        )
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch mode {
        case .prompt: return "moon.stars.fill"
        case .moved: return "arrow.turn.up.right"
        }
    }

    @ViewBuilder
    private var message: some View {
        switch mode {
        case .prompt(let goals):
            (Text(Lp("%d goal left", "%d goals left", goals))
                .foregroundStyle(IslandPalette.primaryText)
             + Text("  ·  " + L("move to tomorrow?"))
                .foregroundStyle(IslandPalette.secondaryText))
                .font(IslandTypography.statusLabel)
                .lineLimit(1)
        case .moved(let goals):
            (Text(L("Moved %d to tomorrow", goals))
                .foregroundStyle(IslandPalette.primaryText))
                .font(IslandTypography.statusLabel)
                .lineLimit(1)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(IslandTypography.statusLabel)
                .foregroundStyle(IslandPalette.primaryText)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius + 1, style: .continuous)
                        .fill(isActionHovered ? IslandPalette.pressedFill : IslandPalette.hoverFill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.95))
        .onHover { isActionHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isActionHovered)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(IslandPalette.tertiaryText)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
        .help(L("Not tonight"))
        .accessibilityLabel(L("Dismiss wrap-up for today"))
    }
}
