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
    /// Small extras shown on the right of the title: moved count, habit streak, tags, steps...
    var accessories = TaskRowAccessories()
    var onOpenDetails: (() -> Void)? = nil
    var onToggleTheOne: (() -> Void)? = nil
    /// Starts or pauses the focus timer on this goal.
    var onToggleTimer: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isCheckHovered = false
    @State private var isPillHovered = false
    @State private var pulse = false
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
            accessoriesView
            trailingChip
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(minHeight: IslandMetrics.rowHeight)
        .background(rowBackground)
        .overlay(alignment: .trailing) {
            if showsHoverActions {
                hoverActions
                    .padding(.trailing, 4)
                    .transition(.opacity)
            }
        }
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .animation(IslandAnimations.hoverFade, value: isLifted)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(L("To do")) { onUpdateStatus(.todo) }
            Button(L("In progress")) { onUpdateStatus(.inProgress) }
            Button(L("Done")) { onUpdateStatus(.done) }
            Divider()
            Button(L("Tomorrow")) { onUpdateStatus(.deferred) }
                .disabled(task.status == .done)
            Divider()
            Button(task.isTimerRunning ? L("Pause timer") : L("Start timer")) { onToggleTimer?() }
                .disabled(task.status == .done || task.status == .deferred)
            Button(task.isTheOne ? L("Remove The One") : L("Make The One")) { onToggleTheOne?() }
                .disabled(task.status == .deferred)
            Button(L("Details…")) { onOpenDetails?() }
            Divider()
            Button(role: .destructive) { onDelete() } label: {
                Label(L("Delete Goal"), systemImage: "trash")
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
        ZStack {
            if task.isTheOne && task.status != .deferred {
                RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                    .fill(IslandPalette.theOneAccent.opacity(task.status == .done ? 0.05 : 0.09))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(IslandPalette.theOneAccent)
                            .frame(width: 2.5, height: 16)
                            .padding(.leading, 1.5)
                            .opacity(task.status == .done ? 0.45 : 1)
                    }
            }
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(isLifted ? IslandPalette.elevatedSurface : (isHovered ? IslandPalette.restFill : Color.clear))
                .overlay {
                    if isLifted {
                        RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                            .strokeBorder(IslandPalette.hairlineStrong, lineWidth: 0.5)
                    }
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
        .help(L("Drag to reorder goal"))
        .accessibilityLabel(L("Reorder %@", task.title))
    }

    private var gripOpacity: Double {
        if isDraggingHandle || isHandleHovered { return 1 }
        return isHovered ? 0.5 : 0
    }

    private var statusButton: some View {
        Button {
            withAnimation(IslandAnimations.statusTransition) {
                toggleQuickStatus()
            }
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
            HStack(spacing: 6) {
                Text(task.title)
                    .font(task.isTheOne ? IslandTypography.taskTitle.weight(.semibold) : IslandTypography.taskTitle)
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
                    .help(L("Double click to edit title"))
                    .accessibilityLabel(accessibilityDescription)
            }
        }
    }

    // MARK: - Accessories

    /// Appears from the second push onwards, and only while the goal is still open.
    private var showsMovedBadge: Bool {
        accessories.deferralCount >= 2 && (task.status == .todo || task.status == .inProgress)
    }

    @ViewBuilder
    private var accessoriesView: some View {
        let hasAny = showsMovedBadge || task.habitID != nil || !accessories.tags.isEmpty
            || !task.subtasks.isEmpty || task.note != nil || task.isTheOne

        if hasAny {
            Button {
                onOpenDetails?()
            } label: {
                HStack(spacing: 7) {
                    if showsMovedBadge {
                        MovedBadgeView(count: accessories.deferralCount)
                    }
                    if task.habitID != nil {
                        HabitChip(streak: accessories.habitStreak ?? 0)
                    }
                    if !accessories.tags.isEmpty {
                        TagDots(tags: accessories.tags)
                    }
                    if !task.subtasks.isEmpty {
                        StepsChip(progress: task.subtaskProgress)
                    }
                    if task.note != nil {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(IslandPalette.tertiaryText)
                            .help(L("Has a note"))
                    }
                    if task.isTheOne {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(IslandPalette.theOneAccent)
                            .help(L("The One: the goal that matters most today"))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Open details"))
            .accessibilityLabel(L("Open details for %@", task.title))
        }
    }


    // MARK: - Trailing controls

    /// The time pill is part of the layout only for goals that are being timed (or in progress);
    /// every other row keeps its full width and gets its actions as a hover overlay instead.
    private var showsTimePill: Bool {
        switch task.status {
        case .inProgress: return true
        case .todo: return task.isTimerRunning || task.timeSpent(at: Date()) >= 1
        case .done, .deferred: return false
        }
    }

    private var showsHoverActions: Bool {
        isHovered && !showsTimePill && task.status != .deferred && !isEditing && !isDraggingHandle
    }

    @ViewBuilder
    private var trailingChip: some View {
        if showsTimePill {
            timePill
        } else if task.status == .deferred {
            statusMenu {
                Text(task.status.displayName)
                    .font(IslandTypography.chip)
                    .foregroundStyle(task.status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                            .fill(task.status.color.opacity(0.12))
                    )
            }
            .help(L("Change status or defer to tomorrow"))
        }
    }

    /// Time spent on the goal (or "In progress" before it has any). Pointing at the pill turns its
    /// leading icon into play / pause, so the timer control lives inside the pill and costs no space.
    private var timePill: some View {
        let running = task.isTimerRunning
        let tint = IslandPalette.inProgressAccent

        return HStack(spacing: 0) {
            Button {
                onToggleTimer?()
            } label: {
                ZStack {
                    if isPillHovered, onToggleTimer != nil {
                        Image(systemName: running ? "pause.fill" : "play.fill")
                            .font(.system(size: 8, weight: .bold))
                    } else if running {
                        Circle()
                            .frame(width: 5, height: 5)
                            .opacity(pulse ? 0.4 : 1)
                    } else if task.timeSpent(at: Date()) >= 1 {
                        Image(systemName: "clock")
                            .font(.system(size: 8, weight: .bold))
                    } else {
                        Circle()
                            .frame(width: 4, height: 4)
                            .opacity(0.5)
                    }
                }
                .foregroundStyle(tint)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onToggleTimer == nil)
            .help(running ? L("Pause the timer") : L("Start the timer"))
            .accessibilityLabel(running ? L("Pause timer for %@", task.title) : L("Start timer for %@", task.title))

            statusMenu {
                pillLabel(running: running)
                    .font(IslandTypography.chip)
                    .foregroundStyle(tint)
                    .padding(.trailing, 7)
                    .frame(height: 20)
                    .contentShape(Rectangle())
            }
            .help(L("Change status or defer to tomorrow"))
        }
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                .fill(tint.opacity(running || isPillHovered ? 0.2 : 0.12))
        )
        .onHover { isPillHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isPillHovered)
        .animation(IslandAnimations.hoverFade, value: running)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: running) { _, _ in startPulseIfNeeded() }
    }

    @ViewBuilder
    private func pillLabel(running: Bool) -> some View {
        if running {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(FocusFormat.clock(task.timeSpent(at: context.date)))
                    .monospacedDigit()
            }
        } else if task.timeSpent(at: Date()) >= 1 {
            Text(FocusFormat.clock(task.timeSpent(at: Date())))
                .monospacedDigit()
        } else {
            Text(TaskStatus.inProgress.displayName)
        }
    }

    private func startPulseIfNeeded() {
        guard task.isTimerRunning else { pulse = false; return }
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { pulse = true }
    }

    /// Actions that appear over the right edge of the row on hover: start the timer, more options.
    private var hoverActions: some View {
        HStack(spacing: 2) {
            if task.status == .todo, onToggleTimer != nil {
                Button {
                    onToggleTimer?()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(IslandPalette.secondaryText)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(IslandPalette.hoverFill))
                        .contentShape(Circle())
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.86))
                .help(L("Start the timer"))
                .accessibilityLabel(L("Start timer for %@", task.title))
            }

            statusMenu {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(IslandPalette.secondaryText)
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .help(L("Change status or defer to tomorrow"))
        }
        .padding(.leading, 26)
        .background(
            // Fades whatever is underneath so the buttons never sit on top of text.
            LinearGradient(
                stops: [
                    .init(color: Self.scrimColor.opacity(0), location: 0),
                    .init(color: Self.scrimColor, location: 0.4),
                    .init(color: Self.scrimColor, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    /// The row's hover wash over the panel, flattened to one opaque color.
    private static let scrimColor = Color(red: 0.085, green: 0.085, blue: 0.09)

    private func statusMenu<Label: View>(@ViewBuilder label: @escaping () -> Label) -> some View {
        TaskStatusMenu(
            currentStatus: task.status,
            isTimerRunning: task.isTimerRunning,
            onSelectStatus: onUpdateStatus,
            onOpenDetails: onOpenDetails,
            onToggleTimer: onToggleTimer,
            onDelete: onDelete,
            label: label
        )
        .fixedSize()
        .accessibilityLabel(L("Change status for %@. Current: %@", task.title, task.status.displayName))
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
            return L("Mark %@ as to do", task.title)
        case .todo, .inProgress:
            return L("Mark %@ as completed", task.title)
        case .deferred:
            return L("Reactivate %@ for today", task.title)
        }
    }

    private var quickStatusTooltip: String {
        switch task.status {
        case .done:
            return L("Mark as To do")
        case .todo, .inProgress:
            return L("Mark as Done")
        case .deferred:
            return L("Deferred to tomorrow")
        }
    }

    private var accessibilityDescription: String {
        L("%@, status: %@", task.title, task.status.displayName)
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

/// "Moved 3x" nudge for goals that keep slipping to the next day. Warms up the more it repeats.
private struct MovedBadgeView: View {
    let count: Int

    private var tint: Color {
        switch count {
        case ..<3: return IslandPalette.deferredAccent
        case 3...4: return IslandPalette.streakAccent
        default: return IslandPalette.destructiveAccent
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 8, weight: .bold))
            Text("\(count)×")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                .fill(tint.opacity(0.13))
        )
        .fixedSize()
        .help(L("Moved to tomorrow %d times", count))
        .accessibilityLabel(L("Moved to tomorrow %d times", count))
    }
}

/// Per-row extras computed by the list so the row itself stays a dumb view.
struct TaskRowAccessories: Equatable {
    var deferralCount: Int = 0
    /// Nil for ordinary goals; the current streak (possibly 0) for habit occurrences.
    var habitStreak: Int? = nil
    var tags: [TagDisplay] = []
}

private struct HabitChip: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 2.5) {
            Image(systemName: "repeat")
                .font(.system(size: 8.5, weight: .bold))
            if streak > 0 {
                Text("\(streak)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(streak > 0 ? IslandPalette.streakAccent : IslandPalette.tertiaryText)
        .help(streak > 0 ? L("Habit · %d-day streak", streak) : L("Habit"))
    }
}

private struct TagDots: View {
    let tags: [TagDisplay]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(tags.prefix(3)) { tag in
                Circle()
                    .fill(tag.color)
                    .frame(width: 6.5, height: 6.5)
            }
            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(IslandPalette.tertiaryText)
            }
        }
        .help(tags.map(\.name).joined(separator: ", "))
    }
}

private struct StepsChip: View {
    let progress: (done: Int, total: Int)

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checklist")
                .font(.system(size: 9, weight: .semibold))
            Text("\(progress.done)/\(progress.total)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(progress.done == progress.total ? IslandPalette.completedAccent : IslandPalette.tertiaryText)
        .help(L("%d of %d steps done", progress.done, progress.total))
    }
}
