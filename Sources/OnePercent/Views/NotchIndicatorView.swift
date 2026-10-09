import SwiftUI

/// The virtual notch: black, flat on top, rounded below. A ring sits on the left and a number on
/// the right, each centred in its side, so the two halves balance around the real notch.
struct NotchIndicatorView: View {
    @ObservedObject var model: NotchIndicatorModel
    @ObservedObject var store: TaskStore
    @ObservedObject var focus: FocusController
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        // One tick per second only while something is timing; otherwise the view is static.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            notch(at: context.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    // MARK: - Content

    private enum Mode {
        case progress
        case stopwatch(TaskItem)
        case focusBlock(PomodoroState)
        case breakBlock(PomodoroState)
    }

    private var mode: Mode {
        guard preferences.indicatorShowsTimer else { return .progress }
        if let block = focus.pomodoro {
            return block.phase == .focus ? .focusBlock(block) : .breakBlock(block)
        }
        if let id = store.runningTimerTaskID, let task = store.allTasks.first(where: { $0.id == id }) {
            return .stopwatch(task)
        }
        return .progress
    }

    @ViewBuilder
    private func notch(at date: Date) -> some View {
        if let layout = model.layout {
            let today = store.tracking.week.last ?? .empty(Date())
            let mode = self.mode
            let height = layout.visibleRect.height

            ZStack(alignment: .top) {
                VirtualNotchShape(bottomRadius: min(12, height * 0.34))
                    .fill(Color.black)

                HStack(spacing: 0) {
                    ring(for: mode, today: today, at: date)
                        .frame(width: 15, height: 15)
                        .frame(width: layout.earWidth, height: height)

                    Color.clear.frame(width: layout.centerGap, height: height)

                    trailingText(for: mode, today: today, at: date)
                        .frame(width: layout.earWidth, height: height)
                }
                .padding(.top, layout.bleed)
            }
            .frame(width: layout.visibleRect.width, height: layout.frame.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibility(for: mode, today: today, at: date))
        }
    }

    private func trailingText(for mode: Mode, today: DayStats, at date: Date) -> some View {
        let text = label(for: mode, today: today, at: date)
        return Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(textColor(for: mode, today: today))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText())
            .padding(.horizontal, 5)
            .animation(.snappy(duration: 0.25), value: text)
    }

    private func textColor(for mode: Mode, today: DayStats) -> Color {
        switch mode {
        case .progress:
            if today.total == 0 { return IslandPalette.tertiaryText }
            return today.isPerfect ? IslandPalette.completedAccent : IslandPalette.primaryText.opacity(0.92)
        case .breakBlock:
            return IslandPalette.theOneAccent
        default:
            return IslandPalette.primaryText.opacity(0.92)
        }
    }

    private func label(for mode: Mode, today: DayStats, at date: Date) -> String {
        switch mode {
        case .progress:
            return today.total == 0 ? "–" : "\(today.completed)/\(today.total)"
        case .stopwatch(let task):
            return FocusFormat.clock(task.timeSpent(at: date))
        case .focusBlock(let block), .breakBlock(let block):
            return FocusFormat.clock(block.remaining(at: date))
        }
    }

    @ViewBuilder
    private func ring(for mode: Mode, today: DayStats, at date: Date) -> some View {
        switch mode {
        case .progress:
            ProgressRing(ratio: today.ratio, isComplete: today.isPerfect, hasGoals: today.total > 0)
        case .stopwatch:
            TimingRing(progress: nil, color: IslandPalette.inProgressAccent, isPaused: false)
        case .focusBlock(let block):
            TimingRing(progress: block.progress(at: date), color: IslandPalette.inProgressAccent, isPaused: block.isPaused)
        case .breakBlock(let block):
            TimingRing(progress: block.progress(at: date), color: IslandPalette.theOneAccent, isPaused: block.isPaused)
        }
    }

    private func accessibility(for mode: Mode, today: DayStats, at date: Date) -> String {
        switch mode {
        case .progress:
            return L("Today: %d of %d goals done", today.completed, today.total)
        case .stopwatch(let task):
            return L("Timing %@, %@", task.title, FocusFormat.clock(task.timeSpent(at: date)))
        case .focusBlock(let block):
            return L("Focus block, %@ left", FocusFormat.clock(block.remaining(at: date)))
        case .breakBlock(let block):
            return L("Break, %@ left", FocusFormat.clock(block.remaining(at: date)))
        }
    }
}

/// Today's completion: a mint arc, a solid disc once everything is done, a faint dashed ring when
/// nothing is planned.
private struct ProgressRing: View {
    let ratio: Double
    let isComplete: Bool
    let hasGoals: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    Color.white.opacity(hasGoals ? 0.18 : 0.14),
                    style: StrokeStyle(lineWidth: 2.2, dash: hasGoals ? [] : [2.2, 2.6])
                )

            Circle()
                .trim(from: 0, to: isComplete ? 1 : CGFloat(ratio))
                .stroke(IslandPalette.completedAccent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1.1)
                .opacity(isComplete ? 0 : (ratio > 0 ? 1 : 0))

            Circle()
                .fill(IslandPalette.completedAccent)
                .scaleEffect(isComplete ? 1 : 0.5)
                .opacity(isComplete ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 7.5, weight: .heavy))
                .foregroundStyle(Color.black.opacity(0.8))
                .scaleEffect(isComplete ? 1 : 0.4)
                .opacity(isComplete ? 1 : 0)
        }
        .animation(IslandAnimations.progressSpring, value: ratio)
        .animation(IslandAnimations.checkSpring, value: isComplete)
    }
}

/// Ring for a running timer: a draining arc for Pomodoro blocks, a breathing dot for the stopwatch.
private struct TimingRing: View {
    let progress: Double?
    let color: Color
    let isPaused: Bool

    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle().strokeBorder(color.opacity(0.28), lineWidth: 2.2)

            if let progress {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.001, 1 - progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.1)
                    .animation(.linear(duration: 1), value: progress)
            }

            if isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(color)
            } else if progress == nil {
                Circle()
                    .fill(color)
                    .frame(width: 5.5, height: 5.5)
                    .opacity(breathing ? 0.45 : 1)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

/// Flat on top (it continues off the screen edge), rounded at the bottom like the hardware notch.
struct VirtualNotchShape: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
            radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
