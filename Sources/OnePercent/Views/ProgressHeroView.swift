import SwiftUI

/// Large percentage with a two-line caption. The numerals roll instead of jumping.
struct ProgressHeroView: View {
    @ObservedObject var store: TaskStore

    private var progress: TaskProgress { store.currentProgress }

    private var isComplete: Bool {
        progress.totalCount > 0 && progress.completedCount == progress.totalCount
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(progress.percentageInt)")
                    .font(IslandTypography.heroNumber)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(progress.percentageInt)))
                Text("%")
                    .font(IslandTypography.heroUnit)
                    .foregroundStyle(isComplete ? IslandPalette.completedAccent.opacity(0.7) : IslandPalette.tertiaryText)
            }
            .foregroundStyle(isComplete ? IslandPalette.completedAccent : IslandPalette.primaryText)
            .frame(minWidth: 68, alignment: .leading)
            .animation(.snappy(duration: 0.38), value: progress.percentageInt)
            .animation(IslandAnimations.hoverFade, value: isComplete)

            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(IslandTypography.heroHeadline)
                    .foregroundStyle(isComplete ? IslandPalette.completedAccent : IslandPalette.primaryText)
                if theOneIsOpen {
                    (Text(Image(systemName: "star.fill")) + Text(" The One is open"))
                        .font(IslandTypography.secondaryMetadata)
                        .foregroundStyle(IslandPalette.theOneAccent)
                } else {
                    Text(subline)
                        .font(IslandTypography.secondaryMetadata)
                        .foregroundStyle(IslandPalette.tertiaryText)
                }
            }
            .contentTransition(.opacity)
            .animation(IslandAnimations.hoverFade, value: headline)
            .animation(IslandAnimations.hoverFade, value: theOneIsOpen)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.dateService.formatProgressHeader(for: store.selectedDate)). \(progress.percentageInt) percent. \(headline), \(subline)")
    }

    /// The single most important goal of the day is still waiting; nudge it into the hero.
    private var theOneIsOpen: Bool {
        guard let theOne = store.theOne(for: store.selectedDate) else { return false }
        return theOne.status == .todo || theOne.status == .inProgress
    }

    private var headline: String {
        if progress.totalCount == 0 {
            return progress.hasOnlyDeferredTasks ? "All moved" : "No goals"
        }
        if isComplete { return "All done" }
        return "\(progress.completedCount) of \(progress.totalCount)"
    }

    private var subline: String {
        if progress.totalCount == 0 {
            return progress.hasOnlyDeferredTasks ? "to tomorrow" : "yet"
        }
        if isComplete { return "Clean sweep" }
        let remaining = progress.totalCount - progress.completedCount
        return "\(remaining) left"
    }
}
