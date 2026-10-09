import SwiftUI
import AppKit

@MainActor
final class IslandPresentationState: ObservableObject {
    @Published var isExpanded: Bool = false

    init(isExpanded: Bool = false) {
        self.isExpanded = isExpanded
    }
}

/// Expanded Dynamic Island notch panel surface per ONE_PERCENT_SPEC.md (Section 11)
struct IslandView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var presentationState: IslandPresentationState
    var onHeightChange: ((CGFloat) -> Void)? = nil
    var onInteractionChange: ((Bool) -> Void)? = nil

    @State private var isAddingTask = false
    @State private var draggedTaskID: UUID? = nil
    @State private var draggedSourceIndex: Int? = nil
    @State private var targetIndex: Int? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var snapshotFrames: [UUID: CGRect] = [:]
    @State private var snapshotTasks: [TaskItem] = []

    /// 0 -> 1 glow around the card when the last open goal of the day is closed.
    @State private var celebrationGlow: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Scroll cues: native indicator is hidden (it covered the status chips), so the list fades at
    // whichever edge still has rows and draws a slim thumb in the card's right gutter instead.
    @State private var listViewportHeight: CGFloat = 0
    @State private var listContentHeight: CGFloat = 0
    @State private var listScrollOffset: CGFloat = 0
    @State private var isScrollThumbActive = false
    @State private var scrollThumbToken = 0

    private let maxVisibleTasksCount = 5
    private let taskRowApproxHeight: CGFloat = IslandMetrics.rowHeight
    private let rowSpacing: CGFloat = IslandMetrics.rowSpacing
    @Namespace private var taskListNamespace

    var body: some View {
        ZStack(alignment: .top) {
            islandCard
                .frame(width: IslandMetrics.panelWidth, height: desiredPanelHeight)
                // Fluid droplet bounce anchored at the camera notch.
                // It expands with overshoot into the window's headroom without edge clipping.
                .scaleEffect(
                    x: presentationState.isExpanded ? 1.0 : 0.70,
                    y: presentationState.isExpanded ? 1.0 : 0.16,
                    anchor: .top
                )
                .opacity(presentationState.isExpanded ? 1.0 : 0.0)
                .animation(
                    presentationState.isExpanded
                        ? IslandAnimations.dropletExpandSpring
                        : IslandAnimations.dropletCollapseSpring,
                    value: presentationState.isExpanded
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, NotchPositionResolver.defaultHeadroom)
        .padding(.bottom, NotchPositionResolver.defaultHeadroom)
        .accessibilityElement(children: .contain)
        .onChange(of: isAddingTask) { _, adding in
            onInteractionChange?(adding)
        }
        .onChange(of: desiredPanelHeight) { _, newHeight in
            onHeightChange?(newHeight)
        }
        .onAppear {
            onHeightChange?(desiredPanelHeight)
        }
    }

    private var islandCard: some View {
        VStack(alignment: .leading, spacing: IslandMetrics.standard) {
            // Hero progress, arrow navigation, and add goal button, with the fill bar tucked underneath
            VStack(alignment: .leading, spacing: 9) {
                IslandHeaderView(
                    store: store,
                    isAddingTask: $isAddingTask
                )

                DailyProgressView(store: store)
            }

            // Discrete error feedback if persistence encountered an error (Section 5.4)
            if let errorMessage = store.lastErrorMessage {
                HStack(spacing: IslandMetrics.compact) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(IslandPalette.destructiveAccent)

                    Text(errorMessage)
                        .font(IslandTypography.caption)
                        .foregroundStyle(IslandPalette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Button("Retry") {
                        store.retrySave()
                    }
                    .buttonStyle(.plain)
                    .font(IslandTypography.caption)
                    .foregroundStyle(IslandPalette.completedAccent)

                    Button {
                        store.clearErrorMessage()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(IslandPalette.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .fill(IslandPalette.destructiveAccent.opacity(0.10))
                )
            }

            // Inline Add Goal Editor
            if isAddingTask {
                AddTaskView(
                    onAdd: { title in
                        store.addTask(title: title)
                        withAnimation(IslandAnimations.defaultSpring) {
                            isAddingTask = false
                        }
                    },
                    onCancel: {
                        withAnimation(IslandAnimations.defaultSpring) {
                            isAddingTask = false
                        }
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                        removal: .opacity
                    )
                )
            }

            // Task List or Empty State
            if store.selectedDateTasks.isEmpty && !isAddingTask {
                EmptyStateView {
                    withAnimation(IslandAnimations.defaultSpring) {
                        isAddingTask = true
                    }
                }
                .frame(maxWidth: .infinity, minHeight: scrollListMaxHeight)
                .transition(.opacity)
            } else if !store.selectedDateTasks.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: rowSpacing) {
                        ForEach(Array(store.selectedDateTasks.enumerated()), id: \.element.id) { index, task in
                            let isBeingDragged = (draggedTaskID == task.id)
                            let currentOffset = calculateRowOffset(for: task, index: index, isBeingDragged: isBeingDragged)

                            TaskRowView(
                                task: task,
                                onUpdateStatus: { newStatus in
                                    let before = store.currentProgress
                                    store.updateTaskStatus(id: task.id, newStatus: newStatus)
                                    let after = store.currentProgress
                                    if before.ratio < 1, after.ratio >= 1, after.totalCount > 0 {
                                        celebrate()
                                    }
                                },
                                onUpdateTitle: { newTitle in
                                    store.updateTaskTitle(id: task.id, newTitle: newTitle)
                                },
                                onDelete: {
                                    withAnimation(IslandAnimations.statusTransition) {
                                        store.deleteTask(id: task.id)
                                    }
                                },
                                onDragStarted: {
                                    draggedTaskID = task.id
                                    draggedSourceIndex = index
                                    targetIndex = index
                                    dragOffset = 0
                                    snapshotFrames = rowFrames
                                    snapshotTasks = store.selectedDateTasks
                                    onInteractionChange?(true)
                                },
                                onDragChanged: { translation in
                                    dragOffset = translation
                                    updateTargetIndex(translation: translation)
                                },
                                onDragEnded: {
                                    commitReorder()
                                },
                                onEditingChanged: { isEditing in
                                    onInteractionChange?(isEditing)
                                },
                                isLifted: isBeingDragged
                            )
                            .matchedGeometryEffect(id: task.id, in: taskListNamespace)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: TaskRowFramePreferenceKey.self,
                                        value: [task.id: geo.frame(in: .named("TaskList"))]
                                    )
                                }
                            )
                            .offset(y: currentOffset)
                            .zIndex(isBeingDragged ? 100 : (store.autoSlidingTaskID == task.id ? 20 : 1))
                            .scaleEffect(isBeingDragged ? 1.015 : (store.autoSlidingTaskID == task.id ? 1.01 : 1.0))
                            .shadow(
                                color: isBeingDragged ? Color.black.opacity(0.45) : (store.autoSlidingTaskID == task.id ? Color.black.opacity(0.25) : Color.clear),
                                radius: isBeingDragged ? 10 : (store.autoSlidingTaskID == task.id ? 4 : 0),
                                x: 0,
                                y: isBeingDragged ? 4 : (store.autoSlidingTaskID == task.id ? 1 : 0)
                            )
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: targetIndex)
                        }
                    }
                    .padding(.vertical, 1)
                    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: store.selectedDateTasks)
                    .background(
                        ScrollMetricsReader { offset, contentHeight, viewportHeight in
                            listScrollOffset = offset
                            listContentHeight = contentHeight
                            listViewportHeight = viewportHeight
                            pulseScrollThumb()
                        }
                    )
                }
                .scrollBounceBehavior(.basedOnSize)
                .coordinateSpace(name: "TaskList")
                .onPreferenceChange(TaskRowFramePreferenceKey.self) { preferences in
                    self.rowFrames = preferences
                }
                // Fill whatever the card has left: with more than five goals the sixth peeks in
                // under the fade, which is what tells you the list continues.
                .frame(maxHeight: .infinity)
                .mask { listEdgeMask }
                .overlay(alignment: .topTrailing) { scrollThumb }
                .animation(IslandAnimations.hoverFade, value: canScrollUp)
                .animation(IslandAnimations.hoverFade, value: canScrollDown)
            }
        }
        .padding(.top, IslandMetrics.mainPadding)
        .padding(.horizontal, IslandMetrics.mainPadding)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardShape.fill(cardFill))
        .clipShape(cardShape)
        .overlay { cardShape.strokeBorder(cardRim, lineWidth: 1) }
        .overlay { celebrationRim }
        // Ultra-diffuse lift; stays inside the window's 24pt headroom so it is never clipped.
        .shadow(color: Color.black.opacity(0.38), radius: 14, x: 0, y: 8)
    }

    // MARK: - Card chrome

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: IslandMetrics.cornerRadius, style: .continuous)
    }

    /// Pure black at the top so the panel fuses with the physical notch, lifting slightly towards the bottom.
    private var cardFill: LinearGradient {
        LinearGradient(
            colors: [IslandPalette.panelTop, IslandPalette.panelBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Rim light that fades out at the very top so no seam shows where the card meets the notch.
    private var cardRim: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.0), location: 0.0),
                .init(color: Color.white.opacity(0.10), location: 0.28),
                .init(color: Color.white.opacity(0.05), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var celebrationRim: some View {
        cardShape
            .strokeBorder(IslandPalette.completedAccent, lineWidth: 1.5)
            .shadow(color: IslandPalette.completedAccent.opacity(0.55), radius: 10)
            .opacity(celebrationGlow)
            .allowsHitTesting(false)
    }

    /// Single, short glow when the last open goal of the day is closed.
    private func celebrate() {
        IslandHaptics.success()
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.25)) { celebrationGlow = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.9)) { celebrationGlow = 0 }
        }
    }

    // MARK: - Scroll cues

    private var listOverflows: Bool {
        listContentHeight > listViewportHeight + 1
    }

    private var canScrollUp: Bool {
        listOverflows && listScrollOffset > 1
    }

    private var canScrollDown: Bool {
        listOverflows && listScrollOffset < listContentHeight - listViewportHeight - 1
    }

    /// Soft fade on each edge that still has rows beyond it; solid when that edge is flush.
    private var listEdgeMask: some View {
        VStack(spacing: 0) {
            listEdgeFade(visible: canScrollUp, leading: true)
            Color.black
            listEdgeFade(visible: canScrollDown, leading: false)
        }
    }

    private func listEdgeFade(visible: Bool, leading: Bool) -> some View {
        ZStack {
            Color.black.opacity(visible ? 0 : 1)
            LinearGradient(
                colors: leading ? [.clear, .black] : [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(visible ? 1 : 0)
        }
        .frame(height: 16)
    }

    /// 2.5pt thumb parked in the 16pt card gutter, so it can never sit on top of a status chip.
    @ViewBuilder
    private var scrollThumb: some View {
        if listOverflows, listViewportHeight > 0 {
            let thumbHeight = max(18, listViewportHeight * listViewportHeight / listContentHeight)
            let travel = max(0, listViewportHeight - thumbHeight)
            let maxOffset = max(1, listContentHeight - listViewportHeight)
            let progress = min(max(listScrollOffset / maxOffset, 0), 1)

            Capsule()
                .fill(Color.white.opacity(isScrollThumbActive ? 0.42 : 0.16))
                .frame(width: 2.5, height: thumbHeight)
                .offset(x: 9, y: progress * travel)
                .animation(IslandAnimations.hoverFade, value: isScrollThumbActive)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func pulseScrollThumb() {
        scrollThumbToken += 1
        let token = scrollThumbToken
        isScrollThumbActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if token == scrollThumbToken {
                isScrollThumbActive = false
            }
        }
    }

    private var scrollListMaxHeight: CGFloat {
        CGFloat(maxVisibleTasksCount) * taskRowApproxHeight
            + CGFloat(maxVisibleTasksCount - 1) * rowSpacing
            + 2
    }

    private var desiredPanelHeight: CGFloat {
        let baseHeight = IslandMetrics.standardPanelHeight
        let errorHeight: CGFloat = store.lastErrorMessage != nil ? 32 : 0
        return min(IslandMetrics.maxPanelHeight, baseHeight + errorHeight)
    }

    private func updateTargetIndex(translation: CGFloat) {
        guard let sIdx = draggedSourceIndex,
              let draggedID = draggedTaskID,
              !snapshotTasks.isEmpty else { return }

        let count = snapshotTasks.count
        guard count > 1 else { return }

        let avgPitch: CGFloat = taskRowApproxHeight + rowSpacing
        let startCenterY = snapshotFrames[draggedID]?.midY ?? (CGFloat(sIdx) * avgPitch + avgPitch / 2)
        let currentCenterY = startCenterY + translation

        func slotCenter(for idx: Int) -> CGFloat {
            let item = snapshotTasks[idx]
            if let frame = snapshotFrames[item.id] {
                return frame.midY
            }
            return startCenterY + CGFloat(idx - sIdx) * avgPitch
        }

        var currentTarget = targetIndex ?? sIdx

        if currentCenterY > slotCenter(for: currentTarget) {
            // User is below current target slot -> evaluating downward movement
            while currentTarget < count - 1 {
                let nextSlot = currentTarget + 1
                let currCenter = slotCenter(for: currentTarget)
                let nextCenter = slotCenter(for: nextSlot)
                let threshold = currCenter + (nextCenter - currCenter) * 0.42
                if currentCenterY > threshold {
                    currentTarget = nextSlot
                } else {
                    break
                }
            }
        } else if currentCenterY < slotCenter(for: currentTarget) {
            // User is above current target slot -> evaluating upward movement
            while currentTarget > 0 {
                let prevSlot = currentTarget - 1
                let currCenter = slotCenter(for: currentTarget)
                let prevCenter = slotCenter(for: prevSlot)
                let threshold = currCenter - (currCenter - prevCenter) * 0.42
                if currentCenterY < threshold {
                    currentTarget = prevSlot
                } else {
                    break
                }
            }
        }

        currentTarget = min(max(0, currentTarget), count - 1)
        if targetIndex != currentTarget {
            targetIndex = currentTarget
        }
    }

    private func calculateRowOffset(for task: TaskItem, index: Int, isBeingDragged: Bool) -> CGFloat {
        if isBeingDragged {
            return dragOffset
        }

        guard let sIdx = draggedSourceIndex,
              let tIdx = targetIndex,
              let draggedID = draggedTaskID,
              sIdx != tIdx else {
            return 0
        }

        let draggedHeight = (snapshotFrames[draggedID]?.height ?? rowFrames[draggedID]?.height ?? taskRowApproxHeight) + rowSpacing

        if sIdx < tIdx {
            // Dragging downwards: items between source and target shift up
            if index > sIdx && index <= tIdx {
                return -draggedHeight
            }
        } else if sIdx > tIdx {
            // Dragging upwards: items between target and source shift down
            if index >= tIdx && index < sIdx {
                return draggedHeight
            }
        }

        return 0
    }

    private func commitReorder() {
        if let sIdx = draggedSourceIndex,
           let tIdx = targetIndex,
           sIdx != tIdx,
           let draggedID = draggedTaskID {
            let tasks = store.selectedDateTasks
            if tIdx >= 0 && tIdx < tasks.count {
                let destinationID = tasks[tIdx].id
                store.moveTask(from: draggedID, to: destinationID)
            }
        }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            draggedTaskID = nil
            draggedSourceIndex = nil
            targetIndex = nil
            dragOffset = 0
            snapshotFrames = [:]
            snapshotTasks = []
        }
        onInteractionChange?(false)
    }
}

private struct TaskRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Reports scroll offset / content height / viewport height of the enclosing `NSScrollView`.
/// SwiftUI on macOS 14 has no scroll-geometry API, so this observes the clip view directly.
private struct ScrollMetricsReader: NSViewRepresentable {
    var onChange: (_ offset: CGFloat, _ contentHeight: CGFloat, _ viewportHeight: CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollMetricsProbeView {
        let view = ScrollMetricsProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ScrollMetricsProbeView, context: Context) {
        nsView.onChange = onChange
        nsView.report()
    }
}

private final class ScrollMetricsProbeView: NSView {
    var onChange: ((CGFloat, CGFloat, CGFloat) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var lastReport: (CGFloat, CGFloat, CGFloat) = (-1, -1, -1)

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attach()
    }

    private func attach() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()

        guard let scrollView = enclosingScrollView else {
            // The hosting layer may not be wired up yet on the first pass.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil, self.enclosingScrollView != nil else { return }
                self.attach()
            }
            return
        }

        scrollView.hasVerticalScroller = false
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clipView, queue: .main
            ) { [weak self] _ in self?.report() }
        )
        if let documentView = scrollView.documentView {
            documentView.postsFrameChangedNotifications = true
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: documentView, queue: .main
                ) { [weak self] _ in self?.report() }
            )
        }
        report()
    }

    func report() {
        guard let scrollView = enclosingScrollView, let documentView = scrollView.documentView else { return }
        let viewport = scrollView.contentView.bounds.height
        let content = documentView.frame.height
        let visible = scrollView.documentVisibleRect
        let offset = documentView.isFlipped ? visible.minY : content - visible.maxY

        let next = (offset.rounded(), content.rounded(), viewport.rounded())
        guard next != lastReport else { return }
        lastReport = next
        onChange?(next.0, next.1, next.2)
    }
}
