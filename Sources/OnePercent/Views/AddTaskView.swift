import SwiftUI
import AppKit

/// What the add editor hands back: a plain goal, or a habit when `schedule` is set.
struct NewGoal: Equatable {
    var title: String
    var tags: [String]
    /// Nil means "the day on screen".
    var date: Date?
    var schedule: HabitSchedule?
}

/// Compact inline goal editor per ONE_PERCENT_SPEC.md (Section 11.5)
///
/// `#tags` are pulled out of the text. When Apple Intelligence is available, longer sentences also
/// go through the on-device model, so "call mom tomorrow #family" lands on tomorrow with a tag.
struct AddTaskView: View {
    @ObservedObject var smartAdd: SmartAddService
    var smartAddEnabled: Bool
    var dateService: DateService
    /// Day the new goal will land on unless the text says otherwise; used to label "Every <weekday>".
    var targetDate: Date
    /// The user's tags with example goals; lets the on-device model tag the goal without a `#`.
    var tagVocabulary: () -> [TagVocabularyEntry] = { [] }
    /// Pre-selected repeat. Only used by previews and tests.
    var initialSchedule: HabitSchedule? = nil
    var onAdd: (NewGoal) -> Void
    var onCancel: () -> Void

    @State private var title: String = ""
    @State private var schedule: HabitSchedule?
    @State private var isThinking = false
    @FocusState private var isFieldFocused: Bool
    @State private var keyMonitor: Any?

    private var usesSmartAdd: Bool { smartAdd.isAvailable && smartAddEnabled }

    var body: some View {
        VStack(spacing: 8) {
            fieldRow

            if let schedule {
                repeatRow(for: schedule)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(IslandAnimations.defaultSpring, value: schedule == nil)
        .onAppear {
            if schedule == nil { schedule = initialSchedule }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
            installKeyMonitor()
            if usesSmartAdd { smartAdd.prewarm() }
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private var fieldRow: some View {
        HStack(spacing: IslandMetrics.compact) {
            leadingIcon

            TextField("", text: $title, prompt: Text(placeholder).foregroundStyle(IslandPalette.tertiaryText))
                .textFieldStyle(.plain)
                .font(IslandTypography.taskTitle)
                .foregroundStyle(IslandPalette.primaryText)
                .focused($isFieldFocused)
                .disabled(isThinking)
                .onSubmit {
                    submit()
                }
                .onExitCommand {
                    onCancel()
                }
                .accessibilityLabel("New goal title")

            repeatMenu

            // Return keycap doubles as the submit button; it lights up once there is something to add.
            Button {
                submit()
            } label: {
                KeycapView(label: "↵", isActive: !trimmedTitle.isEmpty && !isThinking)
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))
            .disabled(trimmedTitle.isEmpty || isThinking)
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
    }

    /// Shown while a repeat is chosen: which weekdays, with the label of what that adds up to.
    private func repeatRow(for schedule: HabitSchedule) -> some View {
        let calendar = dateService.currentCalendar
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "repeat")
                    .font(.system(size: 9, weight: .bold))
                Text(schedule.label(calendar: calendar))
                    .font(IslandTypography.statusLabel)
                Spacer(minLength: 4)
                Text("Tap days to turn them on or off")
                    .font(IslandTypography.statCaption)
                    .foregroundStyle(IslandPalette.tertiaryText)
            }
            .foregroundStyle(IslandPalette.streakAccent)

            WeekdayPickerView(schedule: schedule, calendar: calendar) { self.schedule = $0 }
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var leadingIcon: some View {
        Group {
            if isThinking {
                ProgressView()
                    .controlSize(.mini)
                    .tint(IslandPalette.completedAccent)
            } else {
                Image(systemName: usesSmartAdd ? "sparkles" : "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isFieldFocused ? IslandPalette.completedAccent : IslandPalette.tertiaryText)
            }
        }
        .frame(width: 17, height: 17)
        .accessibilityHidden(true)
    }

    private var placeholder: String {
        usesSmartAdd ? "Try “call mom tomorrow #family”" : "Add a goal for this day"
    }

    private var repeatMenu: some View {
        let weekday = dateService.currentCalendar.component(.weekday, from: targetDate)
        let weeklyLabel = HabitSchedule.weekly(on: weekday).label(calendar: dateService.currentCalendar)

        return Menu {
            Button("Does not repeat") { schedule = nil }
            Divider()
            Button(HabitSchedule.daily.label(calendar: dateService.currentCalendar)) { schedule = .daily }
            Button(HabitSchedule.weekdays.label(calendar: dateService.currentCalendar)) { schedule = .weekdays }
            Button(weeklyLabel) { schedule = .weekly(on: weekday) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .bold))
                if let schedule {
                    Text(shortLabel(for: schedule))
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(schedule == nil ? IslandPalette.tertiaryText : IslandPalette.streakAccent)
            .padding(.horizontal, 5)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                    .fill(schedule == nil ? Color.clear : IslandPalette.streakAccent.opacity(0.14))
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .animation(IslandAnimations.hoverFade, value: schedule)
        .help(schedule == nil ? "Repeat: make this a habit" : "Repeats. Click to change")
        .accessibilityLabel("Repeat")
    }

    private func shortLabel(for schedule: HabitSchedule) -> String {
        switch schedule.kind {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .custom: return "Custom"
        }
    }

    // MARK: - Submit

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedTitle.isEmpty, !isThinking else { return }
        let typed = QuickAddParser.extractTags(from: title)
        guard !typed.title.isEmpty else { return }
        let chosenSchedule = schedule

        let wordCount = typed.title.split(whereSeparator: { $0.isWhitespace }).count
        guard usesSmartAdd, wordCount >= 2 else {
            finish(NewGoal(title: typed.title, tags: typed.tags, date: nil, schedule: chosenSchedule))
            return
        }

        isThinking = true
        let today = dateService.today
        let calendar = dateService.currentCalendar
        let vocabulary = tagVocabulary()
        Task {
            let smart = await smartAdd.parse(typed.title, today: today, calendar: calendar, vocabulary: vocabulary)
            await MainActor.run {
                let merged = NewGoal(
                    title: smart?.title ?? typed.title,
                    tags: QuickAddParserMerge.union(typed.tags, smart?.tags ?? []),
                    date: smart?.date,
                    schedule: chosenSchedule ?? smart?.schedule
                )
                isThinking = false
                finish(merged)
            }
        }
    }

    private func finish(_ goal: NewGoal) {
        onAdd(goal)
        title = ""
        schedule = nil
    }

    // MARK: - Paste

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
}

private enum QuickAddParserMerge {
    static func union(_ first: [String], _ second: [String]) -> [String] {
        var result = first
        for tag in second where !result.contains(tag) { result.append(tag) }
        return result
    }
}
