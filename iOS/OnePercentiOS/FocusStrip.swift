import SwiftUI
import OnePercentCore

/// Shown above the list while something is timing: which goal, how long, pause / resume.
/// In Pomodoro mode it shows the block ("Focus 2 of 4, 18:42 left") and the breaks.
struct FocusStrip: View {
    @ObservedObject var focus: FocusController
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: PhoneFocusSettings

    private var goalID: UUID? { focus.pomodoro?.taskID ?? focus.runningTaskID }
    private var goal: TaskItem? { goalID.flatMap { id in store.allTasks.first { $0.id == id } } }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            strip(at: context.date)
        }
    }

    private func strip(at date: Date) -> some View {
        let block = focus.pomodoro
        let isBreak = block?.phase.isBreak ?? false
        let isPaused = block?.isPaused ?? (focus.runningTaskID == nil)
        let tint = isBreak ? Theme.lavender : Theme.amber

        return HStack(spacing: 12) {
            Image(systemName: isBreak ? "cup.and.saucer.fill" : "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(isBreak: isBreak))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(subtitle(block: block, at: date, isPaused: isPaused))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(clock(block: block, at: date))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isPaused ? Theme.secondaryText : tint)

            if isBreak {
                stripButton("forward.end.fill", label: L("Skip break")) { focus.skipBreak() }
            } else {
                stripButton(isPaused ? "play.fill" : "pause.fill", label: isPaused ? L("Resume") : L("Pause")) {
                    if isPaused { resume() } else { focus.pause() }
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }

    private func stripButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.surfaceStrong))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func title(isBreak: Bool) -> String {
        if isBreak { return focus.pomodoro?.phase == .longBreak ? L("Long break") : L("Break") }
        return goal?.title ?? L("Focus")
    }

    private func subtitle(block: PomodoroState?, at date: Date, isPaused: Bool) -> String {
        if let block {
            if block.phase.isBreak { return L("Back to %@ when it ends", goal?.title ?? L("work")) }
            let number = block.blockNumber(in: settings.pomodoroConfig)
            let total = settings.pomodoroConfig.roundsBeforeLongBreak
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

/// Play / pause for one goal, shown at the end of its row.
struct TimerButton: View {
    let isRunning: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isRunning ? Theme.amber : Theme.secondaryText)
                .frame(width: 34, height: 34)
                .background(Circle().fill(isRunning ? Theme.amber.opacity(0.18) : Theme.surface))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRunning ? L("Pause the timer") : L("Start the timer"))
    }
}

/// The time spent on a goal, ticking while its clock runs.
struct TimeChip: View {
    let task: TaskItem

    var body: some View {
        if task.isTimerRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(FocusFormat.clock(task.timeSpent(at: context.date)), tint: Theme.amber)
            }
        } else if task.timeSpent(at: Date()) >= 1 {
            label(FocusFormat.compact(task.timeSpent(at: Date())), tint: Theme.tertiaryText)
        }
    }

    private func label(_ text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "clock").font(.system(size: 10, weight: .bold))
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(tint)
    }
}
