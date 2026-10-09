import SwiftUI
import OnePercentCore

/// Hand-drawn checkmark so it can be trimmed from nothing to full stroke.
private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.86))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.16))
        return path
    }
}

/// Status glyph for a goal row. All four states stay mounted and cross-animate, so completing a
/// goal draws the check in with a small spring and a one-shot ring pulse instead of swapping icons.
struct StatusMarkView: View {
    let status: TaskStatus
    var isHovered: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 0
    @State private var breathing = false

    private let size: CGFloat = 17

    var body: some View {
        ZStack {
            // Resting ring (to do / in progress / tomorrow)
            Circle()
                .strokeBorder(
                    ringColor,
                    style: StrokeStyle(lineWidth: 1.5, dash: status == .deferred ? [2.4, 2.4] : [])
                )
                .opacity(status == .done ? 0 : 1)

            // In progress: inner dot that breathes very slightly
            Circle()
                .fill(IslandPalette.inProgressAccent)
                .frame(width: 7, height: 7)
                .scaleEffect(status == .inProgress ? 1 : 0.2)
                .opacity(status == .inProgress ? (breathing ? 0.55 : 1) : 0)

            // Tomorrow: small forward chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(IslandPalette.deferredAccent)
                .opacity(status == .deferred ? 1 : 0)
                .offset(x: 0.3)

            // Done: filled disc + trimmed check
            Circle()
                .fill(IslandPalette.completedAccent)
                .scaleEffect(status == .done ? 1 : 0.55)
                .opacity(status == .done ? 1 : 0)

            CheckStroke()
                .trim(from: 0, to: status == .done ? 1 : 0)
                .stroke(
                    Color.black.opacity(0.78),
                    style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 8.5, height: 8.5)

            // One-shot pulse when a goal lands in "done"
            Circle()
                .strokeBorder(IslandPalette.completedAccent, lineWidth: 1.5)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
        }
        .frame(width: size, height: size)
        .animation(IslandAnimations.checkSpring, value: status)
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .onChange(of: status) { _, newStatus in
            if newStatus == .done { firePulse() }
            updateBreathing(for: newStatus)
        }
        .onAppear { updateBreathing(for: status) }
    }

    private var ringColor: Color {
        switch status {
        case .todo: return isHovered ? IslandPalette.secondaryText : IslandPalette.tertiaryText
        case .inProgress: return IslandPalette.inProgressAccent
        case .deferred: return IslandPalette.deferredAccent.opacity(0.8)
        case .done: return IslandPalette.completedAccent
        }
    }

    private func firePulse() {
        guard !reduceMotion else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            pulseScale = 1
            pulseOpacity = 0.6
        }
        // Next runloop turn: SwiftUI would otherwise coalesce both writes and skip the visible start state.
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.5)) {
                pulseScale = 2.0
                pulseOpacity = 0
            }
        }
    }

    private func updateBreathing(for status: TaskStatus) {
        guard !reduceMotion, status == .inProgress else {
            var stop = Transaction()
            stop.disablesAnimations = true
            withTransaction(stop) { breathing = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}
