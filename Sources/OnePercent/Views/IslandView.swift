import SwiftUI

/// Expanded Dynamic Island notch panel surface per ONE_PERCENT_SPEC.md (Section 11)
struct IslandView: View {
    @ObservedObject var store: TaskStore
    var onHeightChange: ((CGFloat) -> Void)? = nil
    var onInteractionChange: ((Bool) -> Void)? = nil

    @State private var isAddingTask = false
    @State private var isCalendarOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: IslandMetrics.standard) {
            // Persistent Header
            IslandHeaderView(
                store: store,
                isAddingTask: $isAddingTask,
                onPopoverChange: { open in
                    isCalendarOpen = open
                }
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
                .transition(.opacity)
            } else if !store.selectedDateTasks.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: IslandMetrics.micro) {
                        ForEach(store.selectedDateTasks) { task in
                            TaskRowView(
                                task: task,
                                onUpdateStatus: { newStatus in
                                    store.updateTaskStatus(id: task.id, newStatus: newStatus)
                                },
                                onDelete: {
                                    withAnimation(IslandAnimations.statusTransition) {
                                        store.deleteTask(id: task.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollBounceBehavior(.basedOnSize)
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
        .accessibilityElement(children: .contain)
        .onChange(of: isAddingTask) { _, adding in
            onInteractionChange?(adding || isCalendarOpen)
        }
        .onChange(of: isCalendarOpen) { _, open in
            onInteractionChange?(isAddingTask || open)
        }
        .onChange(of: desiredPanelHeight) { _, newHeight in
            onHeightChange?(newHeight)
        }
        .onAppear {
            onHeightChange?(desiredPanelHeight)
        }
    }

    private var scrollListMaxHeight: CGFloat {
        IslandMetrics.maxPanelHeight - 130
    }

    private var desiredPanelHeight: CGFloat {
        let baseHeaderAndPadding: CGFloat = 112
        let addEditorHeight: CGFloat = isAddingTask ? 44 : 0
        let errorHeight: CGFloat = store.lastErrorMessage != nil ? 32 : 0
        let listHeight: CGFloat
        if store.selectedDateTasks.isEmpty {
            listHeight = isAddingTask ? 0 : 80
        } else {
            let rowHeight: CGFloat = 37
            listHeight = CGFloat(store.selectedDateTasks.count) * rowHeight
        }

        let total = baseHeaderAndPadding + addEditorHeight + errorHeight + listHeight
        return min(IslandMetrics.maxPanelHeight, max(IslandMetrics.minPanelHeight, total))
    }
}
