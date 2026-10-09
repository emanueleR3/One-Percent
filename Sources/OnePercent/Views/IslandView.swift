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
    @ObservedObject private var preferences: AppPreferences
    @ObservedObject private var focus: FocusController
    private let services: IslandServices
    var onHeightChange: ((CGFloat) -> Void)? = nil
    var onInteractionChange: ((Bool) -> Void)? = nil

    @State private var page: IslandPage = .goals
    @State private var isAddingTask = false
    @State private var draggedTaskID: UUID? = nil
    @State private var draggedSourceIndex: Int? = nil
    @State private var targetIndex: Int? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var snapshotFrames: [UUID: CGRect] = [:]
    @State private var snapshotTasks: [TaskItem] = []

    /// Goals just pushed to tomorrow by the wrap-up prompt; kept for a short Undo window.
    @State private var movedGoalIDs: [UUID]? = nil
    @State private var movedBannerToken = 0

    /// 0 -> 1 glow around the card when the last open goal of the day is closed.
    @State private var celebrationGlow: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let maxVisibleTasksCount = 5
    private let taskRowApproxHeight: CGFloat = IslandMetrics.rowHeight
    private let rowSpacing: CGFloat = IslandMetrics.rowSpacing
    @Namespace private var taskListNamespace

    init(
        store: TaskStore,
        presentationState: IslandPresentationState,
        services: IslandServices,
        onHeightChange: ((CGFloat) -> Void)? = nil,
        onInteractionChange: ((Bool) -> Void)? = nil
    ) {
        self.store = store
        self.presentationState = presentationState
        self._preferences = ObservedObject(wrappedValue: services.preferences)
        self._focus = ObservedObject(wrappedValue: services.focus)
        self.services = services
        self.onHeightChange = onHeightChange
        self.onInteractionChange = onInteractionChange
    }

    var body: some View {
        ZStack(alignment: .top) {
            islandCard
                // Texts are looked up when a view is built, so a language change rebuilds the card.
                .id(preferences.language)
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
        .onChange(of: needsKeyboard) { _, needs in
            onInteractionChange?(needs)
        }
        .onChange(of: presentationState.isExpanded) { _, expanded in
            // Reopen on the goals, not on whichever page was left open.
            if !expanded {
                var noAnimation = Transaction()
                noAnimation.disablesAnimations = true
                withTransaction(noAnimation) {
                    page = .goals
                    isAddingTask = false
                }
            }
        }
        .onChange(of: desiredPanelHeight) { _, newHeight in
            onHeightChange?(newHeight)
        }
        .onAppear {
            onHeightChange?(desiredPanelHeight)
        }
    }

    /// The panel has to stay open and key while text is being typed.
    private var needsKeyboard: Bool {
        isAddingTask || page.isDetail
    }

    private var islandCard: some View {
        VStack(alignment: .leading, spacing: IslandMetrics.standard) {
            // Hero progress with streak / stats / settings / add controls, and the fill bar tucked underneath
            VStack(alignment: .leading, spacing: 9) {
                IslandHeaderView(
                    store: store,
                    page: $page,
                    isAddingTask: $isAddingTask
                )

                DailyProgressView(store: store)
            }

            // Four pages share the space under the bar.
            ZStack(alignment: .top) {
                switch page {
                case .goals:
                    listPage
                        .transition(pageTransition)
                case .stats:
                    StatsView(store: store) { date in
                        withAnimation(IslandAnimations.defaultSpring) {
                            store.selectDate(date)
                            page = .goals
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(pageTransition)
                case .settings:
                    SettingsView(
                        store: store,
                        preferences: preferences,
                        launchAtLogin: services.launchAtLogin,
                        smartAdd: services.smartAdd,
                        reminders: services.reminders
                    )
                    .transition(pageTransition)
                case .detail(let id):
                    GoalDetailView(store: store, preferences: preferences, focusController: focus, taskID: id) {
                        withAnimation(IslandAnimations.defaultSpring) { page = .goals }
                    }
                    .id(id)
                    .transition(pageTransition)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
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

    /// Week strip + day picker, the wrap-up prompt, the add editor, then the goal list (or its empty state).
    private var listPage: some View {
        VStack(alignment: .leading, spacing: IslandMetrics.standard) {
            HStack(spacing: 8) {
                WeekStripView(store: store)

                Spacer(minLength: 6)

                DayPickerView(store: store)
            }

            // Discrete error feedback if persistence encountered an error (Section 5.4)
            if let errorMessage = store.lastErrorMessage {
                errorBanner(errorMessage)
            }

            if focus.isActive {
                FocusStripView(focus: focus, store: store, preferences: preferences)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            if let mode = wrapUpMode {
                WrapUpBannerView(
                    mode: mode,
                    onMove: moveRemainingToTomorrow,
                    onDismiss: dismissWrapUp,
                    onUndo: undoMoveToTomorrow
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }

            // Inline Add Goal Editor
            if isAddingTask {
                AddTaskView(
                    smartAdd: services.smartAdd,
                    smartAddEnabled: preferences.smartAddEnabled,
                    dateService: store.dateService,
                    targetDate: store.selectedDate,
                    tagVocabulary: { store.tagVocabulary() },
                    onAdd: { goal in
                        handleNewGoal(goal)
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
                FadingScrollView(resetToken: AnyHashable(ListResetKey(isOpen: presentationState.isExpanded, day: store.selectedDate))) {
                    VStack(spacing: rowSpacing) {
                        ForEach(Array(store.selectedDateTasks.enumerated()), id: \.element.id) { index, task in
                            taskRow(task, index: index)
                        }
                    }
                    .padding(.vertical, 1)
                    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: store.selectedDateTasks)
                }
                .coordinateSpace(name: "TaskList")
                .onPreferenceChange(TaskRowFramePreferenceKey.self) { preferences in
                    self.rowFrames = preferences
                }
                // Fill whatever the card has left: with more than five goals the sixth peeks in
                // under the fade, which is what tells you the list continues.
                .frame(maxHeight: .infinity)
            }
        }
        .animation(IslandAnimations.defaultSpring, value: wrapUpMode)
        .animation(IslandAnimations.defaultSpring, value: focus.isActive)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// One goal row with its drag, reorder and animation plumbing.
    @ViewBuilder
    private func taskRow(_ task: TaskItem, index: Int) -> some View {
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
                onInteractionChange?(isEditing || needsKeyboard)
            },
            isLifted: isBeingDragged,
            accessories: accessories(for: task),
            onOpenDetails: {
                withAnimation(IslandAnimations.defaultSpring) {
                    page = .detail(task.id)
                }
            },
            onToggleTheOne: {
                withAnimation(IslandAnimations.defaultSpring) {
                    store.toggleTheOne(id: task.id)
                }
            },
            onToggleTimer: {
                focus.toggle(taskID: task.id)
            }
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

    private func errorBanner(_ errorMessage: String) -> some View {
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

            Button(L("Retry")) {
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

    private var pageTransition: AnyTransition {
        .opacity.combined(with: .offset(y: 6))
    }

    // MARK: - Row extras

    private func accessories(for task: TaskItem) -> TaskRowAccessories {
        TaskRowAccessories(
            deferralCount: store.deferralCount(for: task.id),
            habitStreak: task.habitID.map { store.habitStats(for: $0).currentStreak },
            tags: task.tags.map { tag in
                TagDisplay(name: tag, color: TagPalette.color(at: preferences.tagColorIndex(for: tag)))
            }
        )
    }

    // MARK: - Adding goals

    private func handleNewGoal(_ goal: NewGoal) {
        let target = store.dateService.normalize(goal.date ?? store.selectedDate)

        if let schedule = goal.schedule {
            store.addHabit(title: goal.title, schedule: schedule, tags: goal.tags, startDate: target)
        } else {
            store.addTask(title: goal.title, for: target, tags: goal.tags)
        }

        withAnimation(IslandAnimations.defaultSpring) {
            isAddingTask = false
            // "tomorrow" should show tomorrow, so the new goal is visible where it landed.
            let offset = store.dateService.daysFromToday(to: target)
            if target != store.dateService.normalize(store.selectedDate), (-7...7).contains(offset) {
                store.selectDate(target)
            }
        }
    }

    // MARK: - Day wrap-up

    /// Shown after the wrap-up time, only on today, while open goals remain and until dismissed.
    private var wrapUpMode: WrapUpBannerView.Mode? {
        if let moved = movedGoalIDs {
            return .moved(goals: moved.count)
        }
        guard preferences.wrapUp.isEnabled, store.dateService.isToday(store.selectedDate) else { return nil }

        let calendar = store.dateService.currentCalendar
        let now = Date()
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard minutes >= preferences.wrapUp.minutes else { return nil }

        guard !preferences.isWrapUpDismissed(dayKey: store.dateService.dayKey(for: now)) else { return nil }

        let count = store.wrapUpCandidates().count
        return count > 0 ? .prompt(goals: count) : nil
    }

    private func moveRemainingToTomorrow() {
        let ids = store.deferRemaining(for: store.selectedDate)
        guard !ids.isEmpty else { return }
        withAnimation(IslandAnimations.defaultSpring) { movedGoalIDs = ids }

        movedBannerToken += 1
        let token = movedBannerToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if token == movedBannerToken {
                withAnimation(IslandAnimations.defaultSpring) { movedGoalIDs = nil }
            }
        }
    }

    private func undoMoveToTomorrow() {
        guard let ids = movedGoalIDs else { return }
        store.undoDeferral(ids: ids)
        withAnimation(IslandAnimations.defaultSpring) { movedGoalIDs = nil }
    }

    private func dismissWrapUp() {
        withAnimation(IslandAnimations.defaultSpring) {
            preferences.dismissWrapUp(dayKey: store.dateService.dayKey(for: Date()))
        }
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
        onInteractionChange?(needsKeyboard)
    }
}

private struct TaskRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Changes when the list should start from its first row again.
private struct ListResetKey: Hashable {
    let isOpen: Bool
    let day: Date
}
