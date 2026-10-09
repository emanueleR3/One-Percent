import SwiftUI

/// Compact day navigation per user requirements: arrows only, clamped to [-7, +7] days from today
struct DayPickerView: View {
    @ObservedObject var store: TaskStore

    @State private var isLeftHovered = false
    @State private var isRightHovered = false
    @State private var isTitleHovered = false

    private var isToday: Bool {
        store.dateService.isToday(store.selectedDate)
    }

    var body: some View {
        HStack(spacing: 2) {
            chevron(
                systemName: "chevron.left",
                isEnabled: store.canGoToPreviousDay,
                isHovered: isLeftHovered,
                help: store.canGoToPreviousDay ? "Previous day" : "Minimum range reached (-7 days)",
                accessibility: "Go to previous day",
                onHover: { isLeftHovered = $0 }
            ) {
                withAnimation(IslandAnimations.statusTransition) {
                    store.selectPreviousDay()
                }
            }

            // Day title (fixed width so the arrows never shift). Tapping it returns to today.
            Button {
                if !isToday {
                    withAnimation(IslandAnimations.statusTransition) {
                        store.selectToday()
                    }
                }
            } label: {
                Text(store.dateService.formatDayTitle(for: store.selectedDate))
                    .font(IslandTypography.statusLabel)
                    .foregroundStyle(isToday ? IslandPalette.primaryText : IslandPalette.inProgressAccent)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .frame(width: 108, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius + 1, style: .continuous)
                            .fill(isTitleHovered && !isToday ? IslandPalette.hoverFill : IslandPalette.restFill)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.97))
            .onHover { isTitleHovered = $0 }
            .animation(IslandAnimations.hoverFade, value: isTitleHovered)
            .help(isToday ? "Current date: Today" : "Click to jump back to Today")
            .accessibilityLabel("Selected date: \(store.dateService.formatDayTitle(for: store.selectedDate)). \(isToday ? "" : "Click to return to today.")")

            chevron(
                systemName: "chevron.right",
                isEnabled: store.canGoToNextDay,
                isHovered: isRightHovered,
                help: store.canGoToNextDay ? "Next day" : "Maximum range reached (+7 days)",
                accessibility: "Go to next day",
                onHover: { isRightHovered = $0 }
            ) {
                withAnimation(IslandAnimations.statusTransition) {
                    store.selectNextDay()
                }
            }
        }
    }

    private func chevron(
        systemName: String,
        isEnabled: Bool,
        isHovered: Bool,
        help: String,
        accessibility: String,
        onHover: @escaping (Bool) -> Void,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(
                    isEnabled
                        ? (isHovered ? IslandPalette.primaryText : IslandPalette.secondaryText)
                        : IslandPalette.tertiaryText.opacity(0.3)
                )
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius + 1, style: .continuous)
                        .fill(isHovered && isEnabled ? IslandPalette.hoverFill : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
        .disabled(!isEnabled)
        .onHover(perform: onHover)
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .help(help)
        .accessibilityLabel(accessibility)
    }
}
