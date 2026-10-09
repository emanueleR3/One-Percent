import SwiftUI
import OnePercentCore

/// New goal: a title (with `#tags`), a day, and optionally a repeat so it becomes a habit.
struct AddGoalSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var dayOffset: Int
    @State private var repeatChoice: RepeatChoice = .none
    @State private var customDays: Set<Int> = []
    @State private var chosenTags: Set<String> = []
    @FocusState private var titleFocused: Bool

    private enum RepeatChoice { case none, daily, weekdays, custom }

    init(model: AppModel, store: TaskStore) {
        self.model = model
        self.store = store
        let offset = store.dateService.daysFromToday(to: store.selectedDate)
        _dayOffset = State(initialValue: min(max(offset, 0), 7))
    }

    private var calendar: Calendar { store.dateService.currentCalendar }
    private var parsed: QuickAddResult { QuickAddParser.extractTags(from: text) }
    private var canAdd: Bool { !parsed.title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TextField("", text: $text, prompt: Text(L("What's the goal?")).foregroundStyle(Theme.tertiaryText), axis: .vertical)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(.top, 8)

                section(L("Day")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0...7, id: \.self) { offset in
                                ChoiceChip(title: dayTitle(offset), isSelected: dayOffset == offset) { dayOffset = offset }
                            }
                        }
                    }
                }

                section(L("Repeat")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ChoiceChip(title: L("Does not repeat"), isSelected: repeatChoice == .none) { repeatChoice = .none }
                            ChoiceChip(title: L("Every day"), isSelected: repeatChoice == .daily) { repeatChoice = .daily }
                            ChoiceChip(title: L("Weekdays"), isSelected: repeatChoice == .weekdays) { repeatChoice = .weekdays }
                            ChoiceChip(title: L("Custom"), isSelected: repeatChoice == .custom) { repeatChoice = .custom }
                        }
                    }
                    if repeatChoice == .custom {
                        WeekdayToggles(calendar: calendar, selection: $customDays)
                            .padding(.top, 4)
                    }
                }

                if !store.allTagNames.isEmpty {
                    section(L("Tags")) {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(store.allTagNames, id: \.self) { tag in
                                TagToggle(name: tag, color: model.tagColor(tag), isOn: chosenTags.contains(tag) || parsed.tags.contains(tag)) {
                                    if chosenTags.contains(tag) { chosenTags.remove(tag) } else { chosenTags.insert(tag) }
                                }
                            }
                        }
                    }
                }

                Button(action: add) {
                    Text(L("Add goal"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(canAdd ? Color.black.opacity(0.85) : Theme.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(canAdd ? Theme.mint : Theme.surface))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
        .onAppear { titleFocused = true }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Theme.tertiaryText)
            content()
        }
    }

    private func date(for offset: Int) -> Date {
        let today = store.dateService.today
        return store.dateService.normalize(calendar.date(byAdding: .day, value: offset, to: today) ?? today)
    }

    private func dayTitle(_ offset: Int) -> String {
        switch offset {
        case 0: return L("Today")
        case 1: return L("Tomorrow")
        default: return LocalizedDates.string(date(for: offset), template: "EEEd", calendar: calendar)
        }
    }

    private var schedule: HabitSchedule? {
        switch repeatChoice {
        case .none: return nil
        case .daily: return .daily
        case .weekdays: return .weekdays
        case .custom: return .custom(days: Array(customDays))
        }
    }

    private func add() {
        guard canAdd else { return }
        let title = parsed.title.trimmingCharacters(in: .whitespaces)
        var tags = parsed.tags
        for tag in chosenTags.sorted() where !tags.contains(tag) { tags.append(tag) }
        let target = date(for: dayOffset)

        if let schedule {
            _ = store.addHabit(title: title, schedule: schedule, tags: tags, startDate: target)
        } else {
            _ = store.addTask(title: title, for: target, tags: tags)
        }
        // Show the day it landed on.
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { store.selectDate(target) }
        Haptics.tap()
        dismiss()
    }
}

/// A tag that can be switched on or off.
struct TagToggle: View {
    let name: String
    let color: Color
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isOn ? Theme.primaryText : Theme.secondaryText)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(isOn ? color.opacity(0.22) : Theme.surface))
            .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.6) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Tag %@", name))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Seven round switches, starting from the calendar's first weekday.
struct WeekdayToggles: View {
    let calendar: Calendar
    @Binding var selection: Set<Int>

    var body: some View {
        let first = calendar.firstWeekday
        let order = (0..<7).map { (($0 + first - 1) % 7) + 1 }
        HStack(spacing: 8) {
            ForEach(order, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    if isOn { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1].uppercased())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isOn ? Color.black.opacity(0.85) : Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Circle().fill(isOn ? Theme.mint : Theme.surface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
