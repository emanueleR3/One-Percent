import SwiftUI

/// Compact day navigation per user requirements: arrows only, clamped to [-7, +7] days from today
struct DayPickerView: View {
    @ObservedObject var store: TaskStore

    @State private var isLeftHovered = false
    @State private var isRightHovered = false

    var body: some View {
        HStack(spacing: 4) {
            // Previous Day Button (stable hitbox, 26x26)
            Button {
                withAnimation(IslandAnimations.statusTransition) {
                    store.selectPreviousDay()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.canGoToPreviousDay ? (isLeftHovered ? IslandPalette.primaryText : IslandPalette.secondaryText) : IslandPalette.tertiaryText.opacity(0.3))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isLeftHovered && store.canGoToPreviousDay ? IslandPalette.secondarySurface : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.canGoToPreviousDay)
            .onHover { isLeftHovered = $0 }
            .help(store.canGoToPreviousDay ? "Previous day (←)" : "Minimum range reached (-7 days)")
            .accessibilityLabel("Go to previous day")

            // Day Title (Strictly fixed width: 122pt, centered, never shifts the arrows)
            Button {
                if !store.dateService.isToday(store.selectedDate) {
                    withAnimation(IslandAnimations.statusTransition) {
                        store.selectToday()
                    }
                }
            } label: {
                Text(store.dateService.formatDayTitle(for: store.selectedDate))
                    .font(IslandTypography.statusLabel)
                    .foregroundStyle(store.dateService.isToday(store.selectedDate) ? IslandPalette.primaryText : IslandPalette.inProgressAccent)
                    .lineLimit(1)
                    .frame(width: 122, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                            .fill(IslandPalette.secondarySurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                            .stroke(IslandPalette.border.opacity(0.6), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.dateService.isToday(store.selectedDate) ? "Current date: Today" : "Click to jump back to Today")
            .accessibilityLabel("Selected date: \(store.dateService.formatDayTitle(for: store.selectedDate)). \(store.dateService.isToday(store.selectedDate) ? "" : "Click to return to today.")")

            // Next Day Button (stable hitbox, 26x26)
            Button {
                withAnimation(IslandAnimations.statusTransition) {
                    store.selectNextDay()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.canGoToNextDay ? (isRightHovered ? IslandPalette.primaryText : IslandPalette.secondaryText) : IslandPalette.tertiaryText.opacity(0.3))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRightHovered && store.canGoToNextDay ? IslandPalette.secondarySurface : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.canGoToNextDay)
            .onHover { isRightHovered = $0 }
            .help(store.canGoToNextDay ? "Next day (→)" : "Maximum range reached (+7 days)")
            .accessibilityLabel("Go to next day")
        }
        .frame(width: 182)
    }
}
