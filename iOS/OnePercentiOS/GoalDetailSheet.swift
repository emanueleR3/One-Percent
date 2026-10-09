import SwiftUI
import OnePercentCore

/// Everything about one goal: title, status, The One, note, steps and tags.
struct GoalDetailSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: TaskStore
    let taskID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var note = ""
    @State private var newStep = ""
    @State private var newTag = ""
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var focus: Field?

    private enum Field { case title, note, step, tag }

    private var task: TaskItem? { store.allTasks.first { $0.id == taskID } }

    var body: some View {
        Group {
            if let task {
                content(task)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
        .onAppear(perform: load)
        .onDisappear(perform: commit)
    }

    private func load() {
        guard !loaded, let task else { return }
        title = task.title
        note = task.note ?? ""
        loaded = true
    }

    private func commit() {
        guard loaded, task != nil else { return }
        if !title.trimmingCharacters(in: .whitespaces).isEmpty { _ = store.updateTaskTitle(id: taskID, newTitle: title) }
        store.updateNote(id: taskID, note: note)
    }

    private func content(_ task: TaskItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TextField("", text: $title, axis: .vertical)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .focused($focus, equals: .title)
                    .submitLabel(.done)
                    .onSubmit { commit(); focus = nil }
                    .padding(.top, 10)

                statusPicker(task)
                theOneRow(task)
                if let habit = store.habit(for: task.habitID) { habitRow(habit) }

                block(L("Note")) {
                    TextField("", text: $note, prompt: Text(L("Add a note")).foregroundStyle(Theme.tertiaryText), axis: .vertical)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .focused($focus, equals: .note)
                        .lineLimit(2...8)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
                }

                stepsBlock(task)
                tagsBlock(task)

                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(L("Delete goal"), systemImage: "trash")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.destructive.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .confirmationDialog(L("Delete?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button(L("Delete goal"), role: .destructive) {
                        loaded = false   // nothing left to save
                        store.deleteTask(id: taskID)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Theme.tertiaryText)
            content()
        }
    }

    // MARK: Status, The One, habit

    private func statusPicker(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            ForEach([TaskStatus.todo, .inProgress, .done], id: \.self) { status in
                ChoiceChip(title: status.displayName, isSelected: task.status == status) {
                    withAnimation { store.updateTaskStatus(id: taskID, newStatus: status) }
                    Haptics.tap()
                }
            }
            if task.status != .done {
                ChoiceChip(title: L("Tomorrow"), isSelected: task.status == .deferred) {
                    withAnimation { store.updateTaskStatus(id: taskID, newStatus: .deferred) }
                    Haptics.tap()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func theOneRow(_ task: TaskItem) -> some View {
        Button {
            withAnimation { store.toggleTheOne(id: taskID) }
            Haptics.tap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: task.isTheOne ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(task.isTheOne ? Theme.lavender : Theme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.isTheOne ? L("Remove The One") : L("Make The One"))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                    Text(L("The One: the goal that matters most today"))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.tertiaryText)
                }
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(task.isTheOne ? Theme.lavender.opacity(0.14) : Theme.surface))
        }
        .buttonStyle(.plain)
        .disabled(task.status == .deferred)
        .opacity(task.status == .deferred ? 0.45 : 1)
    }

    private func habitRow(_ habit: Habit) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "repeat").foregroundStyle(Theme.orange)
            Text(habit.schedule.label(calendar: store.dateService.currentCalendar))
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            let streak = store.habitStats(for: habit.id).currentStreak
            if streak > 0 { Chip(text: L("%d-day streak", streak), systemImage: "flame.fill", tint: Theme.orange) }
        }
    }

    // MARK: Steps

    private func stepsBlock(_ task: TaskItem) -> some View {
        block(L("Steps")) {
            VStack(spacing: 0) {
                ForEach(task.subtasks) { step in
                    HStack(spacing: 12) {
                        Button {
                            withAnimation { store.toggleSubtask(taskID: taskID, subtaskID: step.id) }
                            Haptics.tap()
                        } label: {
                            Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(step.isDone ? Theme.mint : Theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(step.isDone ? L("Mark step as not done") : L("Mark step as done"))

                        Text(step.title)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(step.isDone ? Theme.tertiaryText : Theme.primaryText)
                            .strikethrough(step.isDone, color: Theme.tertiaryText)
                        Spacer()
                        Button { withAnimation { store.deleteSubtask(taskID: taskID, subtaskID: step.id) } } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.tertiaryText)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("Delete step"))
                    }
                    .padding(.vertical, 8)
                }
                HStack(spacing: 12) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.tertiaryText).frame(width: 22)
                    TextField("", text: $newStep, prompt: Text(L("Add a step")).foregroundStyle(Theme.tertiaryText))
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                        .focused($focus, equals: .step)
                        .submitLabel(.next)
                        .onSubmit {
                            let text = newStep.trimmingCharacters(in: .whitespaces)
                            guard !text.isEmpty else { return }
                            withAnimation { store.addSubtask(to: taskID, title: text) }
                            newStep = ""
                            focus = .step
                        }
                }
                .padding(.vertical, 8)
            }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        }
    }

    // MARK: Tags

    private func tagsBlock(_ task: TaskItem) -> some View {
        let suggestions = store.tagSuggestions(excluding: task.tags)
        return block(L("Tags")) {
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(task.tags, id: \.self) { tag in
                    Button { withAnimation { store.removeTag(tag, from: taskID) } } label: {
                        HStack(spacing: 6) {
                            Circle().fill(model.tagColor(tag)).frame(width: 8, height: 8)
                            Text(tag).font(.system(size: 14, weight: .semibold, design: .rounded))
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiaryText)
                        }
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(model.tagColor(tag).opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Remove tag %@", tag))
                }
                TextField("", text: $newTag, prompt: Text(L("New tag")).foregroundStyle(Theme.tertiaryText))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .focused($focus, equals: .tag)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        withAnimation { store.addTag(newTag, to: taskID) }
                        newTag = ""
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 110, height: 34)
                    .background(Capsule().fill(Theme.surface))
                ForEach(suggestions, id: \.self) { tag in
                    Button { withAnimation { store.addTag(tag, to: taskID) } } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .heavy))
                            Text(tag).font(.system(size: 14, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("Add tag %@", tag))
                }
            }
        }
    }
}
