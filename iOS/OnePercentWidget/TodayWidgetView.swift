import WidgetKit
import SwiftUI

struct TodayEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has run once.
    let snapshot: WidgetSnapshot?

    /// The snapshot only counts for the day it was written.
    var current: WidgetSnapshot? {
        guard let snapshot, snapshot.day == AppGroup.dayKey(for: date) else { return nil }
        return snapshot
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .systemSmall: small
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    // MARK: Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                ProgressRing(ratio: ratio, lineWidth: 8, label: "\(percent)%")
                    .frame(width: 74, height: 74)
                Spacer(minLength: 0)
                streak
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.current?.texts.progress ?? " ")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.primary)
                Text(statusText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 8) {
                ProgressRing(ratio: ratio, lineWidth: 9, label: "\(percent)%")
                    .frame(width: 84, height: 84)
                Text(entry.current?.texts.progress ?? " ")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetPalette.primary)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(statusText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusColor)
                    Spacer()
                    streak
                }
                if let goals = entry.current?.goals, !goals.isEmpty {
                    ForEach(goals.prefix(3)) { goal in
                        HStack(spacing: 8) {
                            Image(systemName: goal.isInProgress ? "circle.inset.filled" : "circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(goal.isInProgress ? WidgetPalette.amber : WidgetPalette.tertiary)
                            Text(goal.title)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(WidgetPalette.primary)
                                .lineLimit(1)
                            if goal.isTheOne {
                                Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(WidgetPalette.lavender)
                            }
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Lock screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            ProgressRing(ratio: ratio, lineWidth: 5, label: "\(percent)", tint: .primary, trackOpacity: 0.25)
                .padding(5)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.current?.texts.progress ?? " ").font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("\(percent)%").font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Text(entry.current?.goals.first?.title ?? statusText)
                .font(.system(size: 12, design: .rounded))
                .lineLimit(1)
            ProgressView(value: ratio)
        }
    }

    // MARK: Pieces

    private var percent: Int { entry.current?.percent ?? 0 }
    private var ratio: Double { Double(percent) / 100 }

    private var statusText: String {
        if let current = entry.current { return current.texts.status }
        return entry.snapshot?.texts.newDay ?? "One Percent"
    }

    private var statusColor: Color {
        guard let current = entry.current else { return WidgetPalette.tertiary }
        return current.total > 0 && current.completed == current.total ? WidgetPalette.mint : WidgetPalette.secondary
    }

    @ViewBuilder
    private var streak: some View {
        if let current = entry.current, current.streak > 0 {
            HStack(spacing: 3) {
                Image(systemName: current.isTodayCounted ? "flame.fill" : "flame")
                Text("\(current.streak)").monospacedDigit()
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(WidgetPalette.orange)
        }
    }
}

struct ProgressRing: View {
    let ratio: Double
    var lineWidth: CGFloat = 8
    var label: String
    var tint: Color = WidgetPalette.mint
    var trackOpacity: Double = 0.12

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(trackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, ratio))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .foregroundStyle(tint == WidgetPalette.mint ? WidgetPalette.primary : tint)
        }
    }
}

enum WidgetPalette {
    static let background = Color(red: 8 / 255, green: 8 / 255, blue: 9 / 255)
    static let primary = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let secondary = Color(red: 161 / 255, green: 161 / 255, blue: 166 / 255)
    static let tertiary = Color(red: 119 / 255, green: 119 / 255, blue: 124 / 255)
    static let mint = Color(red: 143 / 255, green: 215 / 255, blue: 164 / 255)
    static let amber = Color(red: 231 / 255, green: 198 / 255, blue: 110 / 255)
    static let lavender = Color(red: 150 / 255, green: 165 / 255, blue: 255 / 255)
    static let orange = Color(red: 255 / 255, green: 150 / 255, blue: 88 / 255)
    static let track = Color.white.opacity(0.12)
}
