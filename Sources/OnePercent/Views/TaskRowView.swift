import SwiftUI

/// Single task occurrence row per ONE_PERCENT_SPEC.md (Section 11.3)
struct TaskRowView: View {
    let task: TaskItem
    let onUpdateStatus: (TaskStatus) -> Void
    var onUpdateTitle: ((String) -> Void)? = nil
    let onDelete: () -> Void
    var onDragStarted: (() -> Void)? = nil
    var onDragChanged: ((CGFloat) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil
    var onEditingChanged: ((Bool) -> Void)? = nil

    @State private var isHovered = false
    @State private var isHandleHovered = false
    @State private var isDraggingHandle = false
    @State private var isEditing = false
    @State private var editingTitle = ""
    @FocusState private var isFieldFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: IslandMetrics.compact) {
            // 1. Reorder Handle with 3 horizontal lines and immediate hand cursor (BEFORE the check circle)
            ZStack {
                HandCursorRepresentable(cursor: isDraggingHandle ? .closedHand : .openHand)
                    .allowsHitTesting(false)

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isHandleHovered || isDraggingHandle ? IslandPalette.primaryText : IslandPalette.tertiaryText.opacity(0.6))
            }
            .frame(width: 18, height: 24)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHandleHovered = hovering
                if hovering {
                    NSCursor.openHand.set()
                } else if !isDraggingHandle {
                    NSCursor.arrow.set()
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("TaskList"))
                    .onChanged { value in
                        if !isDraggingHandle && !isEditing {
                            isDraggingHandle = true
                            NSCursor.closedHand.set()
                            onDragStarted?()
                        }
                        if !isEditing {
                            onDragChanged?(value.translation.height)
                        }
                    }
                    .onEnded { _ in
                        if !isEditing {
                            isDraggingHandle = false
                            if isHandleHovered {
                                NSCursor.openHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                            onDragEnded?()
                        }
                    }
            )
            .help("Drag to reorder goal")
            .accessibilityLabel("Reorder \(task.title)")

            // 2. Status Icon Button (Check circle)
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

            // 3. Title or Inline Editor (Double click to edit)
            if isEditing {
                TextField("", text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(IslandTypography.taskTitle)
                    .foregroundStyle(IslandPalette.primaryText)
                    .focused($isFieldFocused)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(IslandPalette.secondarySurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(IslandPalette.completedAccent.opacity(0.8), lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit {
                        commitEditing()
                    }
                    .onExitCommand {
                        cancelEditing()
                    }
                    .onChange(of: isFieldFocused) { _, focused in
                        if !focused && isEditing {
                            commitEditing()
                        }
                    }
            } else {
                Text(task.title)
                    .font(IslandTypography.taskTitle)
                    .foregroundStyle(titleColor)
                    .strikethrough(task.status == .done, color: IslandPalette.secondaryText.opacity(0.6))
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        startEditing()
                    }
                    .help("Double click to edit title")
                    .accessibilityLabel(accessibilityDescription)
            }

            // 4. Status Badge with Contextual Menu (pinned to trailing edge, fixed size)
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
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(IslandPalette.secondarySurface, in: RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .stroke(IslandPalette.border.opacity(0.6), lineWidth: 0.5)
                }
            }
            .fixedSize()
            .help("Change status or defer to tomorrow")
            .accessibilityLabel("Change status for \(task.title). Current: \(task.status.displayName)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
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
        .onDisappear {
            removeKeyMonitor()
            if isEditing {
                onEditingChanged?(false)
            }
        }
    }

    private func startEditing() {
        editingTitle = task.title
        isEditing = true
        onEditingChanged?(true)
        installKeyMonitor()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFieldFocused = true
        }
    }

    private func commitEditing() {
        removeKeyMonitor()
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != task.title {
            onUpdateTitle?(trimmed)
        }
        isEditing = false
        onEditingChanged?(false)
    }

    private func cancelEditing() {
        removeKeyMonitor()
        editingTitle = task.title
        isEditing = false
        onEditingChanged?(false)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if isEditing, event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
                if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                    self.editingTitle += pasted
                    return nil
                }
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
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

private struct HandCursorRepresentable: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> HandCursorNSView {
        let view = HandCursorNSView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: HandCursorNSView, context: Context) {
        nsView.cursor = cursor
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

private final class HandCursorNSView: NSView {
    var cursor: NSCursor = .openHand {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }
}
