import SwiftUI

/// Compact header view per ONE_PERCENT_SPEC.md (Section 11.1)
/// Hero progress on the left; streak, stats and add controls on the right.
struct IslandHeaderView: View {
    @ObservedObject var store: TaskStore
    @Binding var isAddingTask: Bool
    @Binding var showStats: Bool

    @State private var isAddHovered = false
    @State private var isStatsHovered = false

    var body: some View {
        HStack(spacing: 6) {
            ProgressHeroView(store: store)

            Spacer(minLength: 6)

            StreakChipView(
                streak: store.tracking.currentStreak,
                best: store.tracking.bestStreak,
                isTodayCounted: store.tracking.isTodayCounted
            ) {
                toggleStats()
            }

            statsButton
            addButton
        }
    }

    private func toggleStats() {
        withAnimation(IslandAnimations.defaultSpring) {
            if !showStats { isAddingTask = false }
            showStats.toggle()
        }
    }

    private var statsButton: some View {
        Button {
            toggleStats()
        } label: {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(showStats || isStatsHovered ? IslandPalette.primaryText : IslandPalette.secondaryText)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                        .fill(showStats ? IslandPalette.pressedFill : (isStatsHovered ? IslandPalette.hoverFill : IslandPalette.restFill))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.92))
        .onHover { isStatsHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isStatsHovered)
        .animation(IslandAnimations.hoverFade, value: showStats)
        .help(showStats ? "Back to goals" : "Stats")
        .accessibilityLabel(showStats ? "Back to goals" : "Show stats")
    }

    /// "+" opens the goal editor; from the stats page it also returns to the list first.
    private var addButton: some View {
        let isOpen = isAddingTask && !showStats

        return Button {
            withAnimation(IslandAnimations.defaultSpring) {
                if showStats {
                    showStats = false
                    isAddingTask = true
                } else {
                    isAddingTask.toggle()
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isOpen || isAddHovered ? IslandPalette.primaryText : IslandPalette.secondaryText)
                .rotationEffect(.degrees(isOpen ? 45 : 0))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                        .fill(isOpen ? IslandPalette.pressedFill : (isAddHovered ? IslandPalette.hoverFill : IslandPalette.restFill))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.92))
        .onHover { isAddHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isAddHovered)
        .animation(IslandAnimations.defaultSpring, value: isOpen)
        .keyboardShortcut("n", modifiers: .command)
        .help(isOpen ? "Close goal input (Esc)" : "Add new goal (⌘N)")
        .accessibilityLabel(isOpen ? "Close goal input" : "Add new goal")
    }
}
