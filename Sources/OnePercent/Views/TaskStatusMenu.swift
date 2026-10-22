import SwiftUI
import OnePercentCore

/// Status menu control presenting the 4 task statuses
struct TaskStatusMenu<LabelContent: View>: View {
    let currentStatus: TaskStatus
    var isTimerRunning: Bool = false
    let onSelectStatus: (TaskStatus) -> Void
    var onOpenDetails: (() -> Void)? = nil
    var onToggleTimer: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @ViewBuilder let label: () -> LabelContent

    var body: some View {
        Menu {
            if let onOpenDetails {
                Section {
                    Button {
                        onOpenDetails()
                    } label: {
                        Label(L("Details…"), systemImage: "list.bullet.indent")
                    }
                }
            }

            if let onToggleTimer, currentStatus == .todo || currentStatus == .inProgress {
                Section {
                    Button {
                        onToggleTimer()
                    } label: {
                        Label(isTimerRunning ? L("Pause timer") : L("Start timer"), systemImage: isTimerRunning ? "pause.fill" : "play.fill")
                    }
                }
            }

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
                        Label(L("Delete Goal"), systemImage: "trash")
                    }
                }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
