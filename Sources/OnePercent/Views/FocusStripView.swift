import SwiftUI
import OnePercentCore

/// Slim bar above the goal list while something is timing: which goal, how long, pause / resume.
/// In Pomodoro mode it shows the block ("Focus 2 of 4, 18:42 left") and the breaks.
struct FocusStripView: View {
    @ObservedObject var focus: FocusController
    @ObservedObject var store: TaskStore
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            strip(at: context.date)
        }
    }

    // MARK: - Content

    private var goalID: UUID? { focus.pomodoro?.taskID ?? focus.runningTaskID }

    private var goal: TaskItem? {
        goalID.flatMap { id in store.allTasks.first { $0.id == id } }
    }

    private func strip(at date: Date) -> some View {
        let block = focus.pomodoro
        let isBreak = block?.phase.isBreak ?? false
        let isPaused = block?.isPaused ?? (focus.runningTaskID == nil)
        let tint = isBreak ? IslandPalette.theOneAccent : IslandPalette.inProgressAccent

        return HStack(spacing: 9) {
            Image(systemName: isBreak ? "cup.and.saucer.fill" : "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title(isBreak: isBreak))
                    .font(IslandTypography.statusLabel)
                    .foregroundStyle(IslandPalette.primaryText)
                    .lineLimit(1)
                Text(subtitle(block: block, at: date, isPaused: isPaused))
                    .font(IslandTypography.statCaption)
                    .foregroundStyle(IslandPalette.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(clock(block: block, at: date))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isPaused ? IslandPalette.secondaryText : tint)

            if isBreak {
                StripButton(systemName: "forward.end.fill", help: L("Skip break")) { focus.skipBreak() }
            } else {
                StripButton(
                    systemName: isPaused ? "play.fill" : "pause.fill",
                    help: isPaused ? L("Resume") : L("Pause")
                ) {
                    if isPaused { resume() } else { focus.pause() }
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .accessibilityElement(children: .contain)
    }

    private func title(isBreak: Bool) -> String {
        if isBreak { return focus.pomodoro?.phase == .longBreak ? L("Long break") : L("Break") }
        return goal?.title ?? L("Focus")
    }

    private func subtitle(block: PomodoroState?, at date: Date, isPaused: Bool) -> String {
        if let block {
            if block.phase.isBreak { return L("Back to %@ when it ends", goal?.title ?? L("work")) }
            let number = block.blockNumber(in: preferences.pomodoroConfig)
            let total = preferences.pomodoroConfig.roundsBeforeLongBreak
            return (isPaused ? L("Paused") + " · " : "") + L("Focus %d of %d", number, total)
        }
        guard let goal else { return isPaused ? L("Paused") : L("Timing") }
        return (isPaused ? L("Paused") + " · " : "") + L("%@ on this goal", FocusFormat.compact(goal.timeSpent(at: date)))
    }

    private func clock(block: PomodoroState?, at date: Date) -> String {
        if let block { return FocusFormat.clock(block.remaining(at: date)) }
        return FocusFormat.clock(goal?.timeSpent(at: date) ?? 0)
    }

    private func resume() {
        if focus.pomodoro != nil {
            focus.resume()
        } else if let id = goalID {
            focus.start(taskID: id)
        }
    }
}

private struct StripButton: View {
    let systemName: String
    let help: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(isHovered ? IslandPalette.primaryText : IslandPalette.secondaryText)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius + 1, style: .continuous)
                        .fill(isHovered ? IslandPalette.hoverFill : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .help(help)
        .accessibilityLabel(help)
    }
}
