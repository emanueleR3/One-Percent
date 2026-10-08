import SwiftUI

/// Daily progress bar and completion summary per ONE_PERCENT_SPEC.md (Section 8, 11.2)
struct DailyProgressView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: IslandMetrics.micro) {
            HStack {
                Text(store.dateService.formatProgressHeader(for: store.selectedDate))
                    .font(IslandTypography.caption)
                    .foregroundStyle(IslandPalette.tertiaryText)
                    .accessibilityHidden(true)

                Spacer(minLength: 8)

                Text(store.currentProgress.summaryText)
                    .font(IslandTypography.progressIndicator)
                    .foregroundStyle(IslandPalette.secondaryText)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(IslandPalette.secondarySurface)
                        .frame(height: 3.5)

                    Capsule()
                        .fill(IslandPalette.completedAccent)
                        .frame(
                            width: max(0, min(geometry.size.width, geometry.size.width * CGFloat(store.currentProgress.ratio))),
                            height: 3.5
                        )
                        .animation(IslandAnimations.progressTransition, value: store.currentProgress.ratio)
                }
            }
            .frame(height: 3.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.dateService.formatProgressHeader(for: store.selectedDate)), \(store.currentProgress.summaryText)")
    }
}
