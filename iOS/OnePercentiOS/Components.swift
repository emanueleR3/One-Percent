import SwiftUI
import UIKit
import OnePercentCore

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// Wraps its children onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += lineHeight + lineSpacing; lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += lineHeight + lineSpacing; lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// The round mark in front of a goal: empty, half full, ticked or "moved on".
struct StatusMark: View {
    let status: TaskStatus
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            switch status {
            case .todo:
                Circle().strokeBorder(Theme.tertiaryText, lineWidth: 2)
            case .inProgress:
                Circle().strokeBorder(Theme.amber, lineWidth: 2)
                Circle().fill(Theme.amber).frame(width: size * 0.4, height: size * 0.4)
            case .done:
                Circle().fill(Theme.mint)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .heavy))
                    .foregroundStyle(Color.black.opacity(0.8))
            case .deferred:
                Circle().strokeBorder(Theme.slate.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                Image(systemName: "chevron.right")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(Theme.slate)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: status)
    }
}

/// Small rounded chip: a tag, a count, a label.
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = Theme.secondaryText

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// Square icon button used in the header.
struct IconButton: View {
    let systemName: String
    let label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Selectable pill (day, repeat choice, language).
struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Theme.mint : Theme.secondaryText)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(isSelected ? Theme.mint.opacity(0.16) : Theme.surface))
                .overlay(Capsule().strokeBorder(isSelected ? Theme.mint.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
