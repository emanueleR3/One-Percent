import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner and Dynamic Island for a running timer or Pomodoro block.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenTimer(title: context.attributes.title, state: context.state)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .activityBackgroundTint(WidgetPalette.background)
                .activitySystemActionForegroundColor(WidgetPalette.mint)
        } dynamicIsland: { context in
            let state = context.state
            let tint = TimerStyle.tint(for: state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: TimerStyle.symbol(for: state))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: state)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.label)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(WidgetPalette.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetPalette.primary)
                        .lineLimit(1)
                        .privacySensitive()
                }
            } compactLeading: {
                Image(systemName: TimerStyle.symbol(for: state))
                    .foregroundStyle(tint)
            } compactTrailing: {
                TimerText(state: state)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: TimerStyle.symbol(for: state))
                    .foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

private struct LockScreenTimer: View {
    let title: String
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        let tint = TimerStyle.tint(for: state)
        HStack(spacing: 12) {
            Image(systemName: TimerStyle.symbol(for: state))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.isBreak ? state.label : title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.primary)
                    .lineLimit(1)
                    .privacySensitive(!state.isBreak)
                Text(state.isBreak ? title : state.label)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(WidgetPalette.tertiary)
                    .lineLimit(1)
                    .privacySensitive(state.isBreak)
            }

            Spacer(minLength: 8)

            TimerText(state: state)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
    }
}

/// The clock itself. The system keeps it moving; paused shows a fixed time.
private struct TimerText: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        Group {
            switch state.kind {
            case .stopwatch:
                Text(state.start, style: .timer)
            case .countdown:
                if let end = state.end, end > state.start {
                    Text(timerInterval: state.start...end, countsDown: true)
                } else {
                    Text("0:00")
                }
            case .paused:
                Text(Self.clock(state.frozen ?? 0))
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
        .minimumScaleFactor(0.7)
        .lineLimit(1)
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private enum TimerStyle {
    static func symbol(for state: FocusActivityAttributes.ContentState) -> String {
        if state.isBreak { return "cup.and.saucer.fill" }
        return state.kind == .paused ? "pause.fill" : "timer"
    }

    static func tint(for state: FocusActivityAttributes.ContentState) -> Color {
        if state.isBreak { return WidgetPalette.lavender }
        return state.kind == .paused ? WidgetPalette.secondary : WidgetPalette.amber
    }
}
