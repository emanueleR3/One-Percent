import SwiftUI

/// Thin daily progress bar per ONE_PERCENT_SPEC.md (Section 8, 11.2). The numbers live in
/// `ProgressHeroView`; this view is only the glanceable fill.
struct DailyProgressView: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        let ratio = CGFloat(store.currentProgress.ratio)

        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(IslandPalette.track)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [IslandPalette.completedAccent, IslandPalette.completedHighlight],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, min(geometry.size.width, geometry.size.width * ratio)))
                    .shadow(color: IslandPalette.completedAccent.opacity(ratio > 0 ? 0.45 : 0), radius: 5)
                    .animation(IslandAnimations.progressSpring, value: ratio)
            }
        }
        .frame(height: IslandMetrics.progressBarHeight)
        .accessibilityHidden(true)
    }
}
