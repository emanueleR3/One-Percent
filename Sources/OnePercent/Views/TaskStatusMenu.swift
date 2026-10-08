import SwiftUI

/// Status menu control presenting the 4 defined task statuses per ONE_PERCENT_SPEC.md (Section 11.4)
struct TaskStatusMenu<LabelContent: View>: View {
    let currentStatus: TaskStatus
    let onSelectStatus: (TaskStatus) -> Void
    var onDelete: (() -> Void)? = nil
    @ViewBuilder let label: () -> LabelContent

    var body: some View {
        Menu {
            Section {
                Button {
                    onSelectStatus(.todo)
                } label: {
                    Label(TaskStatus.todo.displayName, systemImage: TaskStatus.todo.iconName)
                }

                Button {
                    onSelectStatus(.inProgress)
                } label: {
                    Label(TaskStatus.inProgress.displayName, systemImage: TaskStatus.inProgress.iconName)
                }

                Button {
                    onSelectStatus(.done)
                } label: {
                    Label(TaskStatus.done.displayName, systemImage: TaskStatus.done.iconName)
                }
            }

            Section {
                Button {
                    onSelectStatus(.deferred)
                } label: {
                    Label(TaskStatus.deferred.displayName, systemImage: TaskStatus.deferred.iconName)
                }
                .disabled(currentStatus == .done)
            }

            if let onDelete {
                Section {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete Goal", systemImage: "trash")
                    }
                }
            }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }
}
