import SwiftUI

/// Compact empty state view per ONE_PERCENT_SPEC.md (Section 11.6)
struct EmptyStateView: View {
    var onAddGoal: () -> Void

    @State private var isButtonHovered = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(
                        IslandPalette.tertiaryText.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.2, dash: [2.6, 3.6])
                    )
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandPalette.tertiaryText)
            }
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(L("A fresh start."))
                    .font(IslandTypography.sectionTitle)
                    .foregroundStyle(IslandPalette.primaryText)

                Text(L("Add your first goal."))
                    .font(IslandTypography.secondaryMetadata)
                    .foregroundStyle(IslandPalette.tertiaryText)
            }

            Button {
                onAddGoal()
            } label: {
                HStack(spacing: 6) {
                    Text(L("Add goal"))
                        .font(IslandTypography.statusLabel)
                        .foregroundStyle(IslandPalette.primaryText)
                    KeycapView(label: "⌘N")
                }
                .padding(.leading, 11)
                .padding(.trailing, 7)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                        .fill(isButtonHovered ? IslandPalette.hoverFill : IslandPalette.restFill)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.96))
            .onHover { isButtonHovered = $0 }
            .animation(IslandAnimations.hoverFade, value: isButtonHovered)
            .help(L("Add your first goal for this day"))
            .accessibilityLabel(L("Add your first goal"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 6)
    }
}
