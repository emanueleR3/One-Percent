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
    /// True while the row is being dragged to reorder; draws the raised surface.
    var isLifted: Bool = false

    @State private var isHovered = false
    @State private var isCheckHovered = false
    @State private var isHandleHovered = false
    @State private var isDraggingHandle = false
    @State private var isEditing = false
    @State private var editingTitle = ""
    @FocusState private var isFieldFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            gripHandle
            statusButton
            titleView
            statusControl
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(minHeight: IslandMetrics.rowHeight)
        .background(rowBackground)
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .animation(IslandAnimations.hoverFade, value: isLifted)
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

    // MARK: - Subviews

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
            .fill(isLifted ? IslandPalette.elevatedSurface : (isHovered ? IslandPalette.restFill : Color.clear))
            .overlay {
                if isLifted {
                    RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                        .strokeBorder(IslandPalette.hairlineStrong, lineWidth: 0.5)
                }
            }
    }

    /// Reorder grip. Invisible until the row is hovered so a resting list reads as plain text.
    private var gripHandle: some View {
        ZStack {
            HandCursorRepresentable(cursor: isDraggingHandle ? .closedHand : .openHand)
                .allowsHitTesting(false)

            GripDots()
                .foregroundStyle(isHandleHovered || isDraggingHandle ? IslandPalette.primaryText : IslandPalette.tertiaryText)
                .opacity(gripOpacity)
        }
        .frame(width: 12, height: 24)
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
        .animation(IslandAnimations.hoverFade, value: gripOpacity)
        .help("Drag to reorder goal")
        .accessibilityLabel("Reorder \(task.title)")
    }

    /// Chips for active states are always on; the to do / done ellipsis only appears on hover.
    private var showsStatusControl: Bool {
        switch task.status {
        case .inProgress, .deferred: return true
        case .todo, .done: return isHovered
        }
    }

    private var gripOpacity: Double {
        if isDraggingHandle || isHandleHovered { return 1 }
        return isHovered ? 0.5 : 0
    }

    private var statusButton: some View {
        Button {
            let isCompleting = task.status == .todo || task.status == .inProgress
            withAnimation(IslandAnimations.statusTransition) {
                toggleQuickStatus()
            }
            if isCompleting { IslandHaptics.tick() }
        } label: {
            StatusMarkView(status: task.status, isHovered: isCheckHovered)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.84))
        .onHover { isCheckHovered = $0 }
        .accessibilityLabel(quickStatusAccessibilityLabel)
        .help(quickStatusTooltip)
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditing {
            TextField("", text: $editingTitle)
                .textFieldStyle(.plain)
                .font(IslandTypography.taskTitle)
                .foregroundStyle(IslandPalette.primaryText)
                .focused($isFieldFocused)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(IslandPalette.hoverFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(IslandPalette.completedAccent.opacity(0.55), lineWidth: 1)
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
                .strikethrough(task.status == .done, color: IslandPalette.tertiaryText)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .animation(IslandAnimations.statusTransition, value: task.status)
                .onTapGesture(count: 2) {
                    startEditing()
                }
                .help("Double click to edit title")
                .accessibilityLabel(accessibilityDescription)
        }
    }

    /// Trailing status control. Active states (in progress / tomorrow) keep a tinted chip so they
    /// stay scannable; to do / done only reveal an ellipsis on hover.
    private var statusControl: some View {
        TaskStatusMenu(
            currentStatus: task.status,
            onSelectStatus: onUpdateStatus,
            onDelete: onDelete
        ) {
            switch task.status {
            case .inProgress, .deferred:
                Text(task.status.displayName)
                    .font(IslandTypography.chip)
                    .foregroundStyle(task.status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                            .fill(task.status.color.opacity(0.12))
                    )
            case .todo, .done:
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(IslandPalette.secondaryText)
                    .frame(width: 26, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                            .fill(isHovered ? IslandPalette.restFill : Color.clear)
                    )
            }
        }
        .fixedSize()
        // Applied outside the Menu: its AppKit-backed label ignores opacity set on the label itself.
        .opacity(showsStatusControl ? 1 : 0)
        .allowsHitTesting(showsStatusControl)
        .animation(IslandAnimations.hoverFade, value: showsStatusControl)
        .help("Change status or defer to tomorrow")
        .accessibilityLabel("Change status for \(task.title). Current: \(task.status.displayName)")
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
            return IslandPalette.secondaryText.opacity(0.7)
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

/// 2 x 3 dot grip, drawn rather than an SF Symbol so the weight matches the rest of the row.
private struct GripDots: View {
    var body: some View {
        VStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2.5) {
                    Circle().frame(width: 2.3, height: 2.3)
                    Circle().frame(width: 2.3, height: 2.3)
                }
            }
        }
    }
}
