import SwiftUI

/// What a row or detail page needs to draw one tag.
struct TagDisplay: Identifiable, Equatable {
    let name: String
    let color: Color
    var id: String { name }
}

/// Colored tag pill. With `onRemove` it shows a small x on hover.
struct TagChipView: View {
    let tag: TagDisplay
    var onRemove: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tag.color)
                .frame(width: 6, height: 6)

            Text(tag.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(IslandPalette.primaryText.opacity(0.9))

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(IslandPalette.secondaryText)
                        .frame(width: 10, height: 10)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .frame(width: isHovered ? 10 : 0)
                .accessibilityLabel(L("Remove tag %@", tag.name))
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                .fill(tag.color.opacity(0.14))
        )
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Tag %@", tag.name))
    }
}
