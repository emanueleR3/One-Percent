import SwiftUI

/// Compact header view per ONE_PERCENT_SPEC.md (Section 11.1)
/// Hero progress on the left, day navigation and the add button on the right.
struct IslandHeaderView: View {
    @ObservedObject var store: TaskStore
    @Binding var isAddingTask: Bool

    @State private var isAddHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressHeroView(store: store)

            Spacer(minLength: 6)

            // Day navigation controls (arrow-only, [-7, +7] range)
            DayPickerView(store: store)

            addButton
        }
    }

    private var addButton: some View {
        Button {
            withAnimation(IslandAnimations.defaultSpring) {
                isAddingTask.toggle()
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isAddingTask || isAddHovered ? IslandPalette.primaryText : IslandPalette.secondaryText)
                .rotationEffect(.degrees(isAddingTask ? 45 : 0))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                        .fill(isAddingTask ? IslandPalette.pressedFill : (isAddHovered ? IslandPalette.hoverFill : IslandPalette.restFill))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.92))
        .onHover { isAddHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isAddHovered)
        .animation(IslandAnimations.defaultSpring, value: isAddingTask)
        .keyboardShortcut("n", modifiers: .command)
        .help(isAddingTask ? "Close goal input (Esc)" : "Add new goal (⌘N)")
        .accessibilityLabel(isAddingTask ? "Close goal input" : "Add new goal")
    }
}
