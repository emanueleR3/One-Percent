import SwiftUI

/// Compact day navigation per user requirements: arrows only, clamped to [-7, +7] days from today
struct DayPickerView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        HStack(spacing: 5) {
            // Previous Day Button (disabled at -7 days from today)
            Button {
                withAnimation(IslandAnimations.statusTransition) {
                    store.selectPreviousDay()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.canGoToPreviousDay ? IslandPalette.secondaryText : IslandPalette.tertiaryText.opacity(0.35))
                    .frame(width: 18, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!store.canGoToPreviousDay)
            .help(store.canGoToPreviousDay ? "Previous day" : "Minimum range reached (-7 days)")
            .accessibilityLabel("Go to previous day")

            // Day Title (clean, no calendar popover)
            Text(store.dateService.formatDayTitle(for: store.selectedDate))
                .font(IslandTypography.statusLabel)
                .foregroundStyle(store.dateService.isToday(store.selectedDate) ? IslandPalette.primaryText : IslandPalette.inProgressAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .fill(IslandPalette.secondarySurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .stroke(IslandPalette.border.opacity(0.6), lineWidth: 0.5)
                )
                .accessibilityLabel("Selected date: \(store.dateService.formatDayTitle(for: store.selectedDate))")

            // Next Day Button (disabled at +7 days from today)
            Button {
                withAnimation(IslandAnimations.statusTransition) {
                    store.selectNextDay()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.canGoToNextDay ? IslandPalette.secondaryText : IslandPalette.tertiaryText.opacity(0.35))
                    .frame(width: 18, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(!store.canGoToNextDay)
            .help(store.canGoToNextDay ? "Next day" : "Maximum range reached (+7 days)")
            .accessibilityLabel("Go to next day")

            // Quick "Today" Jump Button when viewing another day
            if !store.dateService.isToday(store.selectedDate) {
                Button {
                    withAnimation(IslandAnimations.statusTransition) {
                        store.selectToday()
                    }
                } label: {
                    Text("Today")
                        .font(IslandTypography.caption)
                        .foregroundStyle(IslandPalette.completedAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(IslandPalette.completedAccent.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .help("Jump back to today")
                .accessibilityLabel("Return to today")
            }
        }
    }
}
