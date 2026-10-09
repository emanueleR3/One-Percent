import SwiftUI

/// Everything about one goal that does not fit on a row: tags, steps, a note, The One.
struct GoalDetailView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var focusController: FocusController
    let taskID: UUID
    var onClose: () -> Void

    private enum Field { case title, tag, step, note }

    @State private var title = ""
    @State private var note = ""
    @State private var newTag = ""
    @State private var newStep = ""
    @State private var didLoad = false
    @State private var noteSave: Task<Void, Never>?
    @FocusState private var focus: Field?

    private var task: TaskItem? {
        store.allTasks.first { $0.id == taskID }
    }

    var body: some View {
        Group {
            if let task {
                content(for: task)
            } else {
                Color.clear.onAppear { onClose() }
            }
        }
        .onAppear { loadIfNeeded() }
        .onDisappear { flushNote() }
        .onExitCommand { onClose() }
    }

    // MARK: - Layout

    private func content(for task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(for: task)

            FadingScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let habit = store.habit(for: task.habitID) {
                        habitLine(habit)
                    }
                    focusSection(for: task)
                    tagsSection(for: task)
                    stepsSection(for: task)
                    noteSection
                    deleteRow
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func header(for task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(IslandPalette.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                            .fill(IslandPalette.restFill)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))
            .help(L("Back to goals (Esc)"))
            .accessibilityLabel(L("Back to goals"))

            TextField(L("Goal"), text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(IslandPalette.primaryText)
                .focused($focus, equals: .title)
                .onSubmit { commitTitle() }
                .pasteSupport(text: $title, isActive: focus == .title)
                .onChange(of: focus) { old, _ in
                    if old == .title { commitTitle() }
                }

            theOneButton(for: task)
        }
    }

    private func theOneButton(for task: TaskItem) -> some View {
        Button {
            store.toggleTheOne(id: task.id)
            IslandHaptics.tick()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: task.isTheOne ? "star.fill" : "star")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(L("The One"))
                    .font(IslandTypography.chip)
            }
            .foregroundStyle(task.isTheOne ? IslandPalette.theOneAccent : IslandPalette.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                    .fill(task.isTheOne ? IslandPalette.theOneAccent.opacity(0.16) : IslandPalette.restFill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.94))
        .animation(IslandAnimations.hoverFade, value: task.isTheOne)
        .disabled(task.status == .deferred)
        .help(task.isTheOne ? L("Remove from The One") : L("Make this The One: the single goal that matters most today"))
        .accessibilityLabel(task.isTheOne ? L("Remove The One") : L("Make this The One"))
    }

    private func habitLine(_ habit: Habit) -> some View {
        let stats = store.habitStats(for: habit.id)
        let calendar = store.dateService.currentCalendar
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(IslandPalette.secondaryText)
                Text(habit.schedule.label(calendar: calendar))
                    .font(IslandTypography.statusLabel)
                    .foregroundStyle(IslandPalette.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(stats.currentStreak > 0 ? IslandPalette.streakAccent : IslandPalette.tertiaryText)
                Text("\(stats.currentStreak)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(IslandPalette.primaryText)
                Text(L("best %d", stats.bestStreak))
                    .font(IslandTypography.statCaption)
                    .foregroundStyle(IslandPalette.tertiaryText)
            }

            WeekdayPickerView(schedule: habit.schedule, calendar: calendar) { schedule in
                withAnimation(IslandAnimations.defaultSpring) {
                    store.updateHabitSchedule(id: habit.id, schedule: schedule)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(IslandPalette.restFill)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Focus

    /// Time spent on this goal, with the same play / pause as the row.
    private func focusSection(for task: TaskItem) -> some View {
        let canTime = task.status == .todo || task.status == .inProgress
        let running = task.isTimerRunning
        let sessions = task.focusSessions.count + (running ? 1 : 0)

        return VStack(alignment: .leading, spacing: 7) {
            EyebrowText(L("Focus"))

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    TimelineView(.periodic(from: .now, by: running ? 1 : 3_600)) { context in
                        Text(FocusFormat.clock(task.timeSpent(at: context.date)))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(running ? IslandPalette.inProgressAccent : IslandPalette.primaryText)
                    }
                    Text(sessions == 0 ? L("Not timed yet") : L("%@ · %@ today", Lp("%d session", "%d sessions", sessions), FocusFormat.compact(timeToday(task))))
                        .font(IslandTypography.statCaption)
                        .foregroundStyle(IslandPalette.tertiaryText)
                }

                Spacer(minLength: 6)

                if !task.focusSessions.isEmpty && !running {
                    ResetTimeButton { store.resetFocusTime(id: task.id) }
                }

                if canTime {
                    Button {
                        focusController.toggle(taskID: task.id)
                        IslandHaptics.tick()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: running ? "pause.fill" : "play.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(running ? L("Pause") : (task.focusSessions.isEmpty ? L("Start") : L("Resume")))
                                .font(IslandTypography.statusLabel)
                        }
                        .foregroundStyle(running ? IslandPalette.inProgressAccent : IslandPalette.primaryText)
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                                .fill(running ? IslandPalette.inProgressAccent.opacity(0.16) : IslandPalette.hoverFill)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleButtonStyle(scale: 0.95))
                    .animation(IslandAnimations.hoverFade, value: running)
                    .accessibilityLabel(running ? L("Pause timer") : L("Start timer"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                    .fill(IslandPalette.restFill)
            )
        }
    }

    private func timeToday(_ task: TaskItem) -> TimeInterval {
        let calendar = store.dateService.currentCalendar
        let now = Date()
        var total = task.focusSessions
            .filter { calendar.isDate($0.start, inSameDayAs: now) }
            .reduce(0) { $0 + $1.seconds }
        if let started = task.timerStartedAt, calendar.isDate(started, inSameDayAs: now) {
            total += now.timeIntervalSince(started)
        }
        return total
    }

    // MARK: - Tags

    private func tagsSection(for task: TaskItem) -> some View {
        let suggestions = store.allTagNames.filter { !task.tags.contains($0) }.prefix(3)

        return VStack(alignment: .leading, spacing: 7) {
            EyebrowText(L("Tags"))

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(task.tags, id: \.self) { tag in
                    TagChipView(tag: display(tag)) {
                        withAnimation(IslandAnimations.defaultSpring) {
                            store.removeTag(tag, from: task.id)
                        }
                    }
                }

                tagField(for: task)

                ForEach(Array(suggestions), id: \.self) { tag in
                    Button {
                        withAnimation(IslandAnimations.defaultSpring) {
                            store.addTag(tag, to: task.id)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 7, weight: .heavy))
                            Text(tag)
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                                .strokeBorder(IslandPalette.hairline, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleButtonStyle(scale: 0.94))
                    .accessibilityLabel(L("Add tag %@", tag))
                }
            }
        }
    }

    private func tagField(for task: TaskItem) -> some View {
        TextField("", text: $newTag, prompt: Text(L("New tag")).foregroundStyle(IslandPalette.tertiaryText))
            .textFieldStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(IslandPalette.primaryText)
            .focused($focus, equals: .tag)
            .frame(width: 62)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                    .fill(IslandPalette.restFill)
            )
            .onSubmit {
                withAnimation(IslandAnimations.defaultSpring) {
                    store.addTag(newTag, to: task.id)
                }
                newTag = ""
                focus = .tag
            }
            .pasteSupport(text: $newTag, isActive: focus == .tag)
            .accessibilityLabel(L("New tag"))
    }

    // MARK: - Steps

    private func stepsSection(for task: TaskItem) -> some View {
        let progress = task.subtaskProgress

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                EyebrowText(L("Steps"))
                Spacer()
                if progress.total > 0 {
                    Text(L("%d of %d", progress.done, progress.total))
                        .font(IslandTypography.statCaption)
                        .foregroundStyle(progress.done == progress.total ? IslandPalette.completedAccent : IslandPalette.tertiaryText)
                }
            }

            ForEach(task.subtasks) { step in
                SubtaskRow(
                    step: step,
                    onToggle: {
                        withAnimation(IslandAnimations.statusTransition) {
                            store.toggleSubtask(taskID: task.id, subtaskID: step.id)
                        }
                        IslandHaptics.tick()
                    },
                    onRename: { store.renameSubtask(taskID: task.id, subtaskID: step.id, title: $0) },
                    onDelete: {
                        withAnimation(IslandAnimations.defaultSpring) {
                            store.deleteSubtask(taskID: task.id, subtaskID: step.id)
                        }
                    }
                )
                .transition(.opacity)
            }

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(focus == .step ? IslandPalette.completedAccent : IslandPalette.tertiaryText)
                    .frame(width: 16, height: 16)

                TextField("", text: $newStep, prompt: Text(L("Add a step")).foregroundStyle(IslandPalette.tertiaryText))
                    .textFieldStyle(.plain)
                    .font(IslandTypography.taskTitle)
                    .foregroundStyle(IslandPalette.primaryText)
                    .focused($focus, equals: .step)
                    .onSubmit {
                        withAnimation(IslandAnimations.defaultSpring) {
                            store.addSubtask(to: task.id, title: newStep)
                        }
                        newStep = ""
                        focus = .step
                    }
                    .pasteSupport(text: $newStep, isActive: focus == .step)
                    .accessibilityLabel(L("New step"))
            }
            .frame(height: 26)
        }
        .animation(IslandAnimations.defaultSpring, value: task.subtasks)
    }

    // MARK: - Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowText(L("Note"))

            TextField("", text: $note, prompt: Text(L("Add a note")).foregroundStyle(IslandPalette.tertiaryText), axis: .vertical)
                .textFieldStyle(.plain)
                .font(IslandTypography.taskTitle)
                .foregroundStyle(IslandPalette.primaryText)
                .lineLimit(2...6)
                .focused($focus, equals: .note)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                        .fill(IslandPalette.restFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                        .strokeBorder(focus == .note ? IslandPalette.completedAccent.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .animation(IslandAnimations.hoverFade, value: focus == .note)
                .pasteSupport(text: $note, isActive: focus == .note)
                .onChange(of: note) { _, _ in scheduleNoteSave() }
                .accessibilityLabel(L("Note"))
        }
    }

    private var deleteRow: some View {
        Button(role: .destructive) {
            let id = taskID
            onClose()
            withAnimation(IslandAnimations.statusTransition) {
                store.deleteTask(id: id)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                Text(L("Delete goal"))
                    .font(IslandTypography.statusLabel)
            }
            .foregroundStyle(IslandPalette.destructiveAccent.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                    .fill(IslandPalette.destructiveAccent.opacity(0.08))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
        .accessibilityLabel(L("Delete goal"))
    }

    // MARK: - Helpers

    private func display(_ tag: String) -> TagDisplay {
        TagDisplay(name: tag, color: TagPalette.color(at: preferences.tagColorIndex(for: tag)))
    }

    private func loadIfNeeded() {
        guard !didLoad, let task else { return }
        didLoad = true
        title = task.title
        note = task.note ?? ""
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            title = task?.title ?? ""
        } else {
            store.updateTaskTitle(id: taskID, newTitle: trimmed)
        }
    }

    private func scheduleNoteSave() {
        noteSave?.cancel()
        noteSave = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            store.updateNote(id: taskID, note: note)
        }
    }

    private func flushNote() {
        noteSave?.cancel()
        if didLoad { store.updateNote(id: taskID, note: note) }
    }
}

// MARK: - Subtask row

private struct SubtaskRow: View {
    let step: SubTask
    var onToggle: () -> Void
    var onRename: (String) -> Void
    var onDelete: () -> Void

    @State private var text = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(step.isDone ? Color.clear : IslandPalette.tertiaryText, lineWidth: 1.3)
                    Circle()
                        .fill(IslandPalette.completedAccent)
                        .scaleEffect(step.isDone ? 1 : 0.4)
                        .opacity(step.isDone ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(Color.black.opacity(0.78))
                        .opacity(step.isDone ? 1 : 0)
                }
                .frame(width: 14, height: 14)
                .frame(width: 16, height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.84))
            .animation(IslandAnimations.checkSpring, value: step.isDone)
            .accessibilityLabel(step.isDone ? L("Mark step as not done") : L("Mark step as done"))

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(IslandTypography.taskTitle)
                .foregroundStyle(step.isDone ? IslandPalette.secondaryText.opacity(0.7) : IslandPalette.primaryText)
                .strikethrough(step.isDone, color: IslandPalette.tertiaryText)
                .focused($isFocused)
                .onSubmit { commit() }
                .pasteSupport(text: $text, isActive: isFocused)
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(IslandPalette.tertiaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.88))
            .opacity(isHovered ? 1 : 0)
            .accessibilityLabel(L("Delete step"))
        }
        .frame(minHeight: 26)
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .onAppear { text = step.title }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            text = step.title
        } else if trimmed != step.title {
            onRename(trimmed)
        }
    }
}

/// Clears a goal's tracked time, but only on the second click.
private struct ResetTimeButton: View {
    var onConfirm: () -> Void

    @State private var isArmed = false
    @State private var token = 0

    var body: some View {
        Button {
            if isArmed {
                onConfirm()
                isArmed = false
            } else {
                isArmed = true
                token += 1
                let current = token
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if token == current { isArmed = false }
                }
            }
        } label: {
            Text(isArmed ? L("Clear time?") : L("Reset"))
                .font(IslandTypography.statusLabel)
                .foregroundStyle(isArmed ? IslandPalette.destructiveAccent : IslandPalette.tertiaryText)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                        .fill(isArmed ? IslandPalette.destructiveAccent.opacity(0.14) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.94))
        .animation(IslandAnimations.hoverFade, value: isArmed)
        .accessibilityLabel(isArmed ? L("Confirm clearing tracked time") : L("Reset tracked time"))
    }
}
