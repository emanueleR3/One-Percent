import SwiftUI
import OnePercentCore

/// Compact header view per ONE_PERCENT_SPEC.md (Section 11.1)
/// Hero progress on the left; streak, stats, settings and add controls on the right.
struct IslandHeaderView: View {
    @ObservedObject var store: TaskStore
    @Binding var page: IslandPage
    @Binding var isAddingTask: Bool

    var body: some View {
        HStack(spacing: 6) {
            ProgressHeroView(store: store)

            Spacer(minLength: 6)

            StreakChipView(
                streak: store.tracking.currentStreak,
                best: store.tracking.bestStreak,
                isTodayCounted: store.tracking.isTodayCounted
            ) {
                toggle(.stats)
            }

            HeaderIconButton(
                systemName: "chart.bar.xaxis",
                isActive: page == .stats,
                help: page == .stats ? L("Back to goals") : L("Stats"),
                accessibility: page == .stats ? L("Back to goals") : L("Show stats")
            ) {
                toggle(.stats)
            }

            HeaderIconButton(
                systemName: "gearshape",
                isActive: page == .settings,
                help: page == .settings ? L("Back to goals") : L("Settings"),
                accessibility: page == .settings ? L("Back to goals") : L("Show settings")
            ) {
                toggle(.settings)
            }

            addButton
        }
    }

    private func toggle(_ target: IslandPage) {
        withAnimation(IslandAnimations.defaultSpring) {
            isAddingTask = false
            page = (page == target) ? .goals : target
        }
    }

    /// "+" opens the goal editor; from any other page it also returns to the list first.
    private var addButton: some View {
        let isOpen = isAddingTask && page == .goals

        return HeaderIconButton(
            systemName: "plus",
            isActive: isOpen,
            rotation: isOpen ? 45 : 0,
            help: isOpen ? L("Close goal input (Esc)") : L("Add new goal (⌘N)"),
            accessibility: isOpen ? L("Close goal input") : L("Add new goal")
        ) {
            withAnimation(IslandAnimations.defaultSpring) {
                if page != .goals {
                    page = .goals
                    isAddingTask = true
                } else {
                    isAddingTask.toggle()
                }
            }
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}

/// 26pt square icon button with the panel's hover / press / active treatment.
struct HeaderIconButton: View {
    let systemName: String
    var isActive: Bool = false
    var rotation: Double = 0
    let help: String
    let accessibility: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: systemName == "plus" ? .bold : .semibold))
                .foregroundStyle(isActive || isHovered ? IslandPalette.primaryText : IslandPalette.secondaryText)
                .rotationEffect(.degrees(rotation))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                        .fill(isActive ? IslandPalette.pressedFill : (isHovered ? IslandPalette.hoverFill : IslandPalette.restFill))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.92))
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .animation(IslandAnimations.defaultSpring, value: rotation)
        .animation(IslandAnimations.hoverFade, value: isActive)
        .help(help)
        .accessibilityLabel(accessibility)
    }
}
