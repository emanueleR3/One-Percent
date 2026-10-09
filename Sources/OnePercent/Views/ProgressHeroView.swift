import SwiftUI
import OnePercentCore

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
                    (Text(Image(systemName: "star.fill")) + Text(" " + L("The One is open")))
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
        .accessibilityLabel(L("%@. %d percent. %@, %@", store.dateService.formatProgressHeader(for: store.selectedDate), progress.percentageInt, headline, subline))
    }

    /// The single most important goal of the day is still waiting; nudge it into the hero.
    private var theOneIsOpen: Bool {
        guard let theOne = store.theOne(for: store.selectedDate) else { return false }
        return theOne.status == .todo || theOne.status == .inProgress
    }

    private var headline: String {
        if progress.totalCount == 0 {
            return progress.hasOnlyDeferredTasks ? L("All moved") : L("No goals")
        }
        if isComplete { return L("All done") }
        return L("%d of %d", progress.completedCount, progress.totalCount)
    }

    private var subline: String {
        if progress.totalCount == 0 {
            return progress.hasOnlyDeferredTasks ? L("to tomorrow") : L("yet")
        }
        if isComplete { return L("Clean sweep") }
        let remaining = progress.totalCount - progress.completedCount
        return L("%d left", remaining)
    }
}
