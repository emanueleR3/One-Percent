import SwiftUI

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

    private let maxVisibleTasksCount = 5
    private let taskRowApproxHeight: CGFloat = 28
    private let rowSpacing: CGFloat = 2.5
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
            // Header with wordmark, arrow navigation, and add goal button
            IslandHeaderView(
                store: store,
                isAddingTask: $isAddingTask
            )

            // Daily Progress
            DailyProgressView(store: store)

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
                        .fill(IslandPalette.secondarySurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .stroke(IslandPalette.border.opacity(0.8), lineWidth: 0.5)
                )
            }

            // Hairline separator
            Rectangle()
                .fill(IslandPalette.border.opacity(0.8))
                .frame(height: 1)

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
                .transition(.opacity.combined(with: .move(edge: .top)))
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
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: rowSpacing) {
                        ForEach(Array(store.selectedDateTasks.enumerated()), id: \.element.id) { index, task in
                            let isBeingDragged = (draggedTaskID == task.id)
                            let currentOffset = calculateRowOffset(for: task, index: index, isBeingDragged: isBeingDragged)

                            TaskRowView(
                                task: task,
                                onUpdateStatus: { newStatus in
                                    store.updateTaskStatus(id: task.id, newStatus: newStatus)
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
                            .scaleEffect(isBeingDragged ? 1.02 : (store.autoSlidingTaskID == task.id ? 1.01 : 1.0))
                            .shadow(
                                color: isBeingDragged ? Color.black.opacity(0.4) : (store.autoSlidingTaskID == task.id ? Color.black.opacity(0.25) : Color.clear),
                                radius: isBeingDragged ? 4 : (store.autoSlidingTaskID == task.id ? 3 : 0),
                                x: 0,
                                y: isBeingDragged ? 2 : (store.autoSlidingTaskID == task.id ? 1 : 0)
                            )
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: targetIndex)
                        }
                    }
                    .padding(.vertical, 2)
                    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: store.selectedDateTasks)
                }
                .scrollBounceBehavior(.basedOnSize)
                .coordinateSpace(name: "TaskList")
                .onPreferenceChange(TaskRowFramePreferenceKey.self) { preferences in
                    self.rowFrames = preferences
                }
                .frame(maxHeight: scrollListMaxHeight)
            }
        }
        .padding(IslandMetrics.mainPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(IslandPalette.background)
        .clipShape(RoundedRectangle(cornerRadius: IslandMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IslandMetrics.cornerRadius, style: .continuous)
                .stroke(IslandPalette.border.opacity(0.6), lineWidth: 1)
        }
    }

    private var scrollListMaxHeight: CGFloat {
        CGFloat(maxVisibleTasksCount) * taskRowApproxHeight + 8
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
