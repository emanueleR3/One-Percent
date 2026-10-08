import SwiftUI

/// Single task occurrence row per ONE_PERCENT_SPEC.md (Section 11.3)
struct TaskRowView: View {
    let task: TaskItem
    let onUpdateStatus: (TaskStatus) -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: IslandMetrics.compact) {
            // Status Icon Button
            Button {
                withAnimation(IslandAnimations.statusTransition) {
                    toggleQuickStatus()
                }
            } label: {
                Image(systemName: task.status.iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(task.status.color)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(quickStatusAccessibilityLabel)
            .help(quickStatusTooltip)

            // Title
            Text(task.title)
                .font(IslandTypography.taskTitle)
                .foregroundStyle(titleColor)
                .strikethrough(task.status == .done, color: IslandPalette.secondaryText.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(task.title)
                .accessibilityLabel(accessibilityDescription)

            // Status Badge with Contextual Menu
            TaskStatusMenu(
                currentStatus: task.status,
                onSelectStatus: onUpdateStatus,
                onDelete: onDelete
            ) {
                HStack(spacing: 3) {
                    Text(task.status.displayName)
                        .font(IslandTypography.statusLabel)
                        .foregroundStyle(task.status.color)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(task.status.color.opacity(0.5))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(IslandPalette.secondarySurface, in: RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .stroke(IslandPalette.border.opacity(0.6), lineWidth: 0.5)
                }
                .contentShape(Rectangle())
            }
            .help("Change status or defer to tomorrow")
            .accessibilityLabel("Change status for \(task.title). Current: \(task.status.displayName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(isHovered ? IslandPalette.primarySurface.opacity(0.7) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("To do") { onUpdateStatus(.todo) }
            Button("In progress") { onUpdateStatus(.inProgress) }
            Button("Done") { onUpdateStatus(.done) }
            Divider()
            Button("Tomorrow") { onUpdateStatus(.deferred) }
                .disabled(task.status == .done)
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete Goal", systemImage: "trash")
            }
        }
    }

    private var titleColor: Color {
        switch task.status {
        case .done:
            return IslandPalette.secondaryText
        case .deferred:
            return IslandPalette.tertiaryText
        case .todo, .inProgress:
            return IslandPalette.primaryText
        }
    }

    private func toggleQuickStatus() {
        switch task.status {
        case .todo, .inProgress:
            onUpdateStatus(.done)
        case .done:
            onUpdateStatus(.todo)
        case .deferred:
            // Deferred task: toggle to todo if user explicitly interacts with the icon
            onUpdateStatus(.todo)
        }
    }

    private var quickStatusAccessibilityLabel: String {
        switch task.status {
        case .done:
            return "Mark \(task.title) as to do"
        case .todo, .inProgress:
            return "Mark \(task.title) as completed"
        case .deferred:
            return "Reactivate \(task.title) for today"
        }
    }

    private var quickStatusTooltip: String {
        switch task.status {
        case .done:
            return "Mark as To do"
        case .todo, .inProgress:
            return "Mark as Done"
        case .deferred:
            return "Deferred to tomorrow"
        }
    }

    private var accessibilityDescription: String {
        "\(task.title), status: \(task.status.displayName)"
    }
}
