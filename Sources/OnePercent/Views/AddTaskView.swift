import SwiftUI

/// Compact inline goal editor per ONE_PERCENT_SPEC.md (Section 11.5)
struct AddTaskView: View {
    var onAdd: (String) -> Void
    var onCancel: () -> Void

    @State private var title: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: IslandMetrics.compact) {
            Image(systemName: "plus.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(IslandPalette.secondaryText)
                .accessibilityHidden(true)

            TextField("Add a goal for this day...", text: $title)
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

            // Submit Button
            Button {
                submit()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(trimmedTitle.isEmpty ? IslandPalette.tertiaryText : IslandPalette.completedAccent)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(trimmedTitle.isEmpty)
            .help("Add goal (Return)")
            .accessibilityLabel("Add goal")

            // Cancel Button
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandPalette.secondaryText)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
            .accessibilityLabel("Cancel adding goal")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .fill(IslandPalette.primarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                .stroke(IslandPalette.border, lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
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
