import SwiftUI

/// Compact header view per ONE_PERCENT_SPEC.md (Section 11.1)
struct IslandHeaderView: View {
    @ObservedObject var store: TaskStore
    @Binding var isAddingTask: Bool

    var body: some View {
        HStack(spacing: IslandMetrics.compact) {
            // Wordmark
            Text("One Percent")
                .font(IslandTypography.appWordmark)
                .foregroundStyle(IslandPalette.primaryText)

            Spacer(minLength: 4)

            // Day navigation controls (arrow-only, [-7, +7] range)
            DayPickerView(store: store)

            Spacer(minLength: 4)

            // Add Goal Button
            Button {
                withAnimation(IslandAnimations.defaultSpring) {
                    isAddingTask.toggle()
                }
            } label: {
                Image(systemName: isAddingTask ? "xmark" : "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isAddingTask ? IslandPalette.secondaryText : IslandPalette.primaryText)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(IslandPalette.secondarySurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(IslandPalette.border.opacity(0.8), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help(isAddingTask ? "Close goal input (Esc)" : "Add new goal (⌘N)")
            .accessibilityLabel(isAddingTask ? "Close goal input" : "Add new goal")
        }
    }
}
