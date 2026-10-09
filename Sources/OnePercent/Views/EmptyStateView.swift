import SwiftUI

/// Compact empty state view per ONE_PERCENT_SPEC.md (Section 11.6)
struct EmptyStateView: View {
    var onAddGoal: () -> Void

    var body: some View {
        VStack(spacing: IslandMetrics.compact) {
            VStack(spacing: 2) {
                Text("A fresh start.")
                    .font(IslandTypography.sectionTitle)
                    .foregroundStyle(IslandPalette.primaryText)

                Text("Add your first goal.")
                    .font(IslandTypography.secondaryMetadata)
                    .foregroundStyle(IslandPalette.secondaryText)
            }

            Button {
                onAddGoal()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Add Goal")
                        .font(IslandTypography.statusLabel)
                }
                .foregroundStyle(IslandPalette.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .fill(IslandPalette.secondarySurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .stroke(IslandPalette.border, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help("Add your first goal for this day")
            .accessibilityLabel("Add your first goal")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
    }
}
