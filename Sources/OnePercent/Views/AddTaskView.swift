import SwiftUI
import AppKit

/// Compact inline goal editor per ONE_PERCENT_SPEC.md (Section 11.5)
struct AddTaskView: View {
    var onAdd: (String) -> Void
    var onCancel: () -> Void

    @State private var title: String = ""
    @FocusState private var isFieldFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: IslandMetrics.compact) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isFieldFocused ? IslandPalette.completedAccent : IslandPalette.tertiaryText)
                .frame(width: 17, height: 17)
                .accessibilityHidden(true)

            TextField("Add a goal for this day", text: $title)
                .textFieldStyle(.plain)
                .font(IslandTypography.taskTitle)
                .foregroundStyle(IslandPalette.primaryText)
                .focused($isFieldFocused)
                .onSubmit {
                    submit()
                }
                .onExitCommand {
                    onCancel()
                }
                .accessibilityLabel("New goal title")

            // Return keycap doubles as the submit button; it lights up once there is something to add.
            Button {
                submit()
            } label: {
                KeycapView(label: "↵", isActive: !trimmedTitle.isEmpty)
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))
            .disabled(trimmedTitle.isEmpty)
            .help("Add goal (Return)")
            .accessibilityLabel("Add goal")

            Button {
                onCancel()
            } label: {
                KeycapView(label: "esc")
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))
            .help("Cancel (Esc)")
            .accessibilityLabel("Cancel adding goal")
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(IslandPalette.restFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .strokeBorder(
                    isFieldFocused ? IslandPalette.completedAccent.opacity(0.5) : IslandPalette.hairline,
                    lineWidth: 1
                )
        )
        .animation(IslandAnimations.hoverFade, value: isFieldFocused)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Handle Command+V paste reliably
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
                if let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty {
                    self.title += pasted
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

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedTitle.isEmpty else { return }
        onAdd(trimmedTitle)
        title = ""
    }
}
