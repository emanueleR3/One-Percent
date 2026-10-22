import SwiftUI
import OnePercentCore

/// The home screen: today's progress, the week, and the day's goals.
struct TodayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: TaskStore
    @ObservedObject var focus: FocusController

    @State private var sheet: ActiveSheet?
    @State private var editMode: EditMode = .inactive

    enum ActiveSheet: Identifiable {
        case add
        case detail(UUID)
        case settings
        case stats

        var id: String {
            switch self {
            case .add: return "add"
            case .detail(let id): return "detail-\(id)"
            case .settings: return "settings"
            case .stats: return "stats"
            }
        }
    }

    private var isReordering: Bool { editMode == .active }

    var body: some View {
        let tasks = store.selectedDateTasks
        let summary = store.tracking

        ZStack(alignment: .bottomTrailing) {
            Theme.background.ignoresSafeArea()

            List {
                Group {
                    TodayHeader(
                        progress: store.currentProgress,
                        streak: summary.currentStreak,
                        isTodayCounted: summary.isTodayCounted,
                        hasOpenTheOne: tasks.contains { $0.isTheOne && $0.status != .done && $0.status != .deferred },
                        onStats: { sheet = .stats },
                        onSettings: { sheet = .settings }
                    )
                    .padding(.top, 8)

                    WeekStrip(store: store)
                        .padding(.top, 6)

                    DayBar(store: store)
                        .padding(.vertical, 4)

                    if focus.isActive {
                        FocusStrip(focus: focus, store: store, settings: model.focusSettings)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if tasks.isEmpty {
                    EmptyDay { sheet = .add }
                        .listRowInsets(EdgeInsets(top: 30, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(tasks) { task in
                        GoalRow(
                            task: task,
                            tags: task.tags.map { (name: $0, color: model.tagColor($0)) },
                            habitStreak: task.habitID.map { store.habitStats(for: $0).currentStreak },
                            onToggle: { toggle(task) },
                            onOpen: { sheet = .detail(task.id) },
                            onToggleTimer: { focus.toggle(taskID: task.id); Haptics.tap() }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: isReordering ? 8 : 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        // Quick actions: swipe left for tomorrow / delete, right for The One.
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                withAnimation { store.deleteTask(id: task.id) }
                            } label: { Label(L("Delete goal"), systemImage: "trash") }
                            if task.status == .todo || task.status == .inProgress {
                                Button {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { store.deferTask(id: task.id) }
                                    Haptics.tap()
                                } label: { Label(L("Tomorrow"), systemImage: "arrow.turn.up.right") }
                                    .tint(Theme.slate)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if task.status != .deferred {
                                Button {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { store.toggleTheOne(id: task.id) }
                                    Haptics.tap()
                                } label: { Label(L("The One"), systemImage: task.isTheOne ? "star.slash" : "star.fill") }
                                    .tint(Theme.lavender)
                            }
                        }
                        .contextMenu { contextMenu(for: task) }
                    }
                    .onMove(perform: move)
                }

                // Room under the last goal for the add button.
                Color.clear.frame(height: 90)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: tasks)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: focus.isActive)
            .refreshable { await model.cloud?.syncNow() }
            .id(store.selectedDate)
            .transition(.opacity)

            if isReordering {
                Button { withAnimation { editMode = .inactive } } label: {
                    Label(L("Done"), systemImage: "checkmark")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(.horizontal, 22)
                        .frame(height: 54)
                        .background(Capsule().fill(Theme.mint))
                        .shadow(color: Theme.mint.opacity(0.35), radius: 16, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 22)
                .padding(.bottom, 14)
            } else {
                Button { sheet = .add } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .frame(width: 62, height: 62)
                        .background(Circle().fill(Theme.mint))
                        .shadow(color: Theme.mint.opacity(0.35), radius: 16, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 22)
                .padding(.bottom, 14)
                .accessibilityLabel(L("Add new goal"))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.selectedDate)
        .onAppear(perform: openSheetForInspection)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add: AddGoalSheet(model: model, store: store)
            case .detail(let id): GoalDetailSheet(model: model, store: store, focusController: focus, taskID: id)
            case .settings: SettingsSheet(model: model, store: store)
            case .stats: StatsSheet(model: model, store: store)
            }
        }
    }

    // MARK: Reordering

    private func move(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        let to = destination > from ? destination - 1 : destination
        store.moveTask(from: from, to: to)
    }

    /// Development builds can open a screen at launch (`-demo -demoSheet add|settings|stats|detail`, `-demoFocus`, `-demoRemoteFocus`) to inspect it.
    private func openSheetForInspection() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard model.isDemo else { return }
        if arguments.contains("-demoReorder") { editMode = .active }
        if arguments.contains("-demoFocus"), let first = store.selectedDateTasks.first(where: { $0.status == .inProgress }) {
            focus.start(taskID: first.id)
        }
        // A timer that "arrives from the Mac": applied the way sync applies it, so nothing marks it as ours.
        if arguments.contains("-demoRemoteFocus"),
           var goal = store.selectedDateTasks.first(where: { $0.status == .inProgress }) {
            goal.timerStartedAt = Date().addingTimeInterval(-300)
            goal.updatedAt = Date()
            store.applyRemote(TaskStore.RemoteChanges(tasks: [goal]))
        }
        guard let index = arguments.firstIndex(of: "-demoSheet"), index + 1 < arguments.count else { return }
        switch arguments[index + 1] {
        case "add": sheet = .add
        case "settings": sheet = .settings
        case "stats": sheet = .stats
        case "detail": if let first = store.selectedDateTasks.first { sheet = .detail(first.id) }
        default: break
        }
        #endif
    }

    // MARK: Actions

    private func toggle(_ task: TaskItem) {
        let newStatus: TaskStatus = (task.status == .todo || task.status == .inProgress) ? .done : .todo
        setStatus(task, newStatus)
    }

    private func setStatus(_ task: TaskItem, _ status: TaskStatus) {
        let before = store.currentProgress
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            store.updateTaskStatus(id: task.id, newStatus: status)
        }
        let after = store.currentProgress
        if before.ratio < 1, after.ratio >= 1, after.totalCount > 0 {
            Haptics.success()
        } else {
            Haptics.tap()
        }
    }

    @ViewBuilder
    private func contextMenu(for task: TaskItem) -> some View {
        Button { setStatus(task, .todo) } label: { Label(L("To do"), systemImage: "circle") }
        Button { setStatus(task, .inProgress) } label: { Label(L("In progress"), systemImage: "circle.lefthalf.filled") }
        Button { setStatus(task, .done) } label: { Label(L("Done"), systemImage: "checkmark.circle") }
        if task.status != .done && task.status != .deferred {
            Button { setStatus(task, .deferred) } label: { Label(L("Tomorrow"), systemImage: "arrow.turn.up.right") }
        }
        Divider()
        Button { store.toggleTheOne(id: task.id) } label: {
            Label(task.isTheOne ? L("Remove The One") : L("Make The One"), systemImage: "star")
        }
        Button { withAnimation { editMode = .active } } label: { Label(L("Reorder"), systemImage: "arrow.up.arrow.down") }
        Button { sheet = .detail(task.id) } label: { Label(L("Details…"), systemImage: "list.bullet.indent") }
        Divider()
        Button(role: .destructive) { store.deleteTask(id: task.id) } label: { Label(L("Delete goal"), systemImage: "trash") }
    }
}

private struct EmptyDay: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
            Text(L("Add your first goal for this day"))
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button(action: onAdd) {
                Text(L("Add goal"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.mint)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Capsule().fill(Theme.mint.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One goal in the list: the status mark, the title, what is attached to it and its timer.
struct GoalRow: View {
    let task: TaskItem
    let tags: [(name: String, color: Color)]
    let habitStreak: Int?
    var onToggle: () -> Void
    var onOpen: () -> Void
    var onToggleTimer: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(action: onToggle) {
                StatusMark(status: task.status)
                    .frame(width: 52, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.status == .done ? L("Mark %@ as to do", task.title) : L("Mark %@ as completed", task.title))

            Button(action: onOpen) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title)
                            .font(.system(size: 18, weight: task.isTheOne ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(titleColor)
                            .strikethrough(task.status == .done, color: Theme.tertiaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        accessories
                    }
                    Spacer(minLength: 4)
                    trailing
                }
                .padding(.vertical, 8)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Open details for %@", task.title))

            if canTime {
                TimerButton(isRunning: task.isTimerRunning, action: onToggleTimer)
            }
        }
    }

    private var canTime: Bool { task.status == .todo || task.status == .inProgress }

    private var titleColor: Color {
        switch task.status {
        case .done: return Theme.tertiaryText
        case .deferred: return Theme.secondaryText.opacity(0.7)
        default: return Theme.primaryText
        }
    }

    @ViewBuilder
    private var accessories: some View {
        let hasTime = task.isTimerRunning || task.timeSpent(at: Date()) >= 1
        let hasAny = !tags.isEmpty || !task.subtasks.isEmpty || task.note != nil || habitStreak != nil || hasTime
        if hasAny {
            HStack(spacing: 8) {
                if hasTime { TimeChip(task: task) }
                if let habitStreak {
                    HStack(spacing: 3) {
                        Image(systemName: "repeat").font(.system(size: 10, weight: .bold))
                        if habitStreak > 0 {
                            Text("\(habitStreak)").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                    }
                    .foregroundStyle(habitStreak > 0 ? Theme.orange : Theme.tertiaryText)
                }
                ForEach(tags.prefix(3), id: \.name) { tag in
                    HStack(spacing: 4) {
                        Circle().fill(tag.color).frame(width: 7, height: 7)
                        Text(tag.name).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.secondaryText)
                    }
                }
                if tags.count > 3 {
                    Text("+\(tags.count - 3)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                }
                if !task.subtasks.isEmpty {
                    let progress = task.subtaskProgress
                    HStack(spacing: 3) {
                        Image(systemName: "checklist").font(.system(size: 11, weight: .semibold))
                        Text("\(progress.done)/\(progress.total)").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    }
                    .foregroundStyle(Theme.tertiaryText)
                }
                if task.note != nil {
                    Image(systemName: "text.alignleft").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if task.isTheOne && task.status != .deferred {
            Image(systemName: "star.fill").font(.system(size: 15)).foregroundStyle(Theme.lavender)
        } else if task.status == .deferred {
            Chip(text: L("Tomorrow"), tint: Theme.slate)
        } else if task.status == .inProgress && !task.isTimerRunning {
            Chip(text: L("In progress"), tint: Theme.amber)
        }
    }
}
