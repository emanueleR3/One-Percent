import SwiftUI
import AppKit
import OnePercentCore

/// Preferences page: wrap-up, reminders, general behaviour, habits and tags.
struct SettingsView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    @ObservedObject var smartAdd: SmartAddService
    let reminders: ReminderCoordinator?
    var cloud: CloudSyncController? = nil
    /// Reported up so the panel stays open and takes the keyboard while an email or password is typed.
    @Binding var isTyping: Bool

    @State private var displays: [DisplayInfo] = []
    /// The display the notch lives on; gives the virtual notch its automatic size.
    @State private var notchGeometry: NotchGeometry?

    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 14) {
                wrapUpSection
                remindersSection
                focusSection
                notchSection
                generalSection
                if let cloud {
                    CloudSyncSection(cloud: cloud, calendar: store.dateService.currentCalendar, isTyping: $isTyping)
                }
                habitsSection
                tagsSection
                aboutFooter
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            launchAtLogin.refresh()
            displays = DisplayCatalog.connected()
            refreshNotchGeometry()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            displays = DisplayCatalog.connected()
            refreshNotchGeometry()
        }
        .onChange(of: preferences.screenSelection) { _ in refreshNotchGeometry() }
    }

    // MARK: - Sections

    private var wrapUpSection: some View {
        SettingsSection(L("Day wrap-up")) {
            SettingsRow(title: L("Offer to move what's left"), caption: L("A prompt in the panel after this time")) {
                IslandSwitch(isOn: $preferences.wrapUp.isEnabled)
            }
            SettingsDivider()
            SettingsRow(title: L("After")) {
                TimeStepperView(minutes: $preferences.wrapUp.minutes, isEnabled: preferences.wrapUp.isEnabled)
            }
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        if let reminders {
            RemindersSettingsSection(preferences: preferences, reminders: reminders)
        } else {
            SettingsSection(L("Reminders")) {
                SettingsRow(title: L("Gentle notifications"), caption: L("Available in the installed app")) {
                    IslandSwitch(isOn: .constant(false))
                        .opacity(0.4)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: Focus

    private var focusSection: some View {
        SettingsSection(L("Focus")) {
            SettingsRow(title: L("Pomodoro"), caption: L("Timed blocks with breaks, instead of a free stopwatch")) {
                IslandSwitch(isOn: $preferences.pomodoroEnabled)
            }

            if preferences.pomodoroEnabled {
                SettingsDivider()
                SettingsRow(title: L("Focus block")) {
                    MinuteStepperView(value: $preferences.focusMinutes, range: 5...90, step: 5)
                }
                SettingsDivider()
                SettingsRow(title: L("Short break")) {
                    MinuteStepperView(value: $preferences.shortBreakMinutes, range: 1...30, step: 1)
                }
                SettingsDivider()
                SettingsRow(title: L("Long break"), caption: L("After the last block of a round")) {
                    MinuteStepperView(value: $preferences.longBreakMinutes, range: 5...60, step: 5)
                }
                SettingsDivider()
                SettingsRow(title: L("Blocks per round")) {
                    MinuteStepperView(value: $preferences.pomodoroRounds, range: 2...8, step: 1, unit: "")
                }
            }

            SettingsDivider()
            SettingsRow(title: L("Sound when a block ends")) {
                IslandSwitch(isOn: $preferences.focusSound)
            }
            SettingsDivider()
            SettingsRow(
                title: L("Notification when a block ends"),
                caption: reminders == nil ? L("Available in the installed app") : nil
            ) {
                IslandSwitch(isOn: focusNotificationsBinding)
                    .opacity(reminders == nil ? 0.4 : 1)
                    .allowsHitTesting(reminders != nil)
            }
        }
    }

    private var focusNotificationsBinding: Binding<Bool> {
        Binding(
            get: { preferences.focusNotifications },
            set: { enabled in
                preferences.focusNotifications = enabled
                if enabled, let reminders {
                    Task { await reminders.requestAuthorization() }
                }
            }
        )
    }

    // MARK: Notch

    /// A typical notched MacBook until the real display has been measured.
    private static let fallbackGeometry = NotchGeometry(
        expandedFrame: .zero,
        activationRect: .zero,
        notchBounds: NSRect(x: 666, y: 950, width: 180, height: 32),
        hasPhysicalNotch: true,
        screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982)
    )

    private var sizingGeometry: NotchGeometry { notchGeometry ?? Self.fallbackGeometry }

    private func refreshNotchGeometry() {
        notchGeometry = NotchPositionResolver().resolve(
            selection: preferences.screenSelection,
            anchor: preferences.panelAnchor
        )
    }

    private var notchSection: some View {
        SettingsSection(L("Notch")) {
            SettingsRow(title: L("Virtual notch"), caption: L("A black notch over the real one, with your progress on both sides")) {
                IslandSwitch(isOn: $preferences.indicatorEnabled)
            }

            if preferences.indicatorEnabled {
                SettingsDivider()
                SettingsRow(title: L("Show the timer there"), caption: L("Counts while a goal or a Pomodoro block runs")) {
                    IslandSwitch(isOn: $preferences.indicatorShowsTimer)
                }
                SettingsDivider()
                SettingsRow(title: L("Width"), caption: L("The real notch covers the middle")) {
                    SizeStepperView(
                        value: $preferences.virtualNotchWidth,
                        automatic: Double(VirtualNotchSizing.automaticWidth(for: sizingGeometry)),
                        range: Double(VirtualNotchSizing.widthRange(for: sizingGeometry).lowerBound)...Double(VirtualNotchSizing.widthRange(for: sizingGeometry).upperBound),
                        accessibility: L("Width")
                    )
                }
                SettingsDivider()
                SettingsRow(title: L("Height"), caption: L("Match it to your notch")) {
                    SizeStepperView(
                        value: $preferences.virtualNotchHeight,
                        automatic: Double(VirtualNotchSizing.automaticHeight(for: sizingGeometry)),
                        range: Double(VirtualNotchSizing.heightRange(for: sizingGeometry).lowerBound)...Double(VirtualNotchSizing.heightRange(for: sizingGeometry).upperBound),
                        accessibility: L("Height")
                    )
                }
            }

            SettingsDivider()
            SettingsRow(title: L("Panel position"), caption: L("On displays without a notch")) {
                OptionChips(
                    options: [
                        .init(label: L("Left"), value: PanelAnchor.leading),
                        .init(label: L("Center"), value: PanelAnchor.center),
                        .init(label: L("Right"), value: PanelAnchor.trailing)
                    ],
                    selection: $preferences.panelAnchor,
                    accessibility: L("Panel position")
                )
            }
            SettingsDivider()
            SettingsRow(title: L("Open delay"), caption: L("Rest on the notch before it opens")) {
                OptionChips(
                    options: Self.openDelayOptions,
                    selection: $preferences.openDelay,
                    accessibility: L("Open delay")
                )
            }
            SettingsDivider()
            SettingsRow(title: L("Close delay"), caption: L("Stays open after the pointer leaves")) {
                OptionChips(
                    options: Self.closeDelayOptions,
                    selection: $preferences.closeDelay,
                    accessibility: L("Close delay")
                )
            }

            SettingsDivider()
            displayChoices
        }
    }

    private static var openDelayOptions: [OptionChips<Double>.Option] { [
        .init(label: L("Instant"), value: 0), .init(label: "0.2s", value: 0.2),
        .init(label: "0.4s", value: 0.4), .init(label: "0.8s", value: 0.8)
    ] }

    private static var closeDelayOptions: [OptionChips<Double>.Option] { [
        .init(label: L("Quick"), value: 0.16), .init(label: "0.4s", value: 0.4),
        .init(label: "0.8s", value: 0.8), .init(label: "1.2s", value: 1.2)
    ] }

    /// Which display hosts the panel: automatic, the menu-bar one, or a specific one.
    private var displayChoices: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Display"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(IslandPalette.primaryText)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            DisplayChoiceRow(
                title: L("Automatic"),
                caption: L("The built-in display, else the main one"),
                isSelected: preferences.screenSelection == .automatic
            ) { preferences.screenSelection = .automatic }

            DisplayChoiceRow(
                title: L("Main display"),
                caption: L("Whichever has the menu bar"),
                isSelected: preferences.screenSelection == .main
            ) { preferences.screenSelection = .main }

            ForEach(displays) { display in
                DisplayChoiceRow(
                    title: display.name,
                    caption: display.hasNotch ? L("Has a notch") : (display.isBuiltIn ? L("Built-in") : L("External")),
                    isSelected: preferences.screenSelection == .display(display.id)
                ) { preferences.screenSelection = .display(display.id) }
            }
            Spacer().frame(height: 4)
        }
    }

    private var generalSection: some View {
        SettingsSection(L("General")) {
            SettingsRow(title: L("Language"), caption: L("Applies right away")) {
                OptionChips(
                    options: [
                        .init(label: L("System"), value: LanguageChoice.system),
                        .init(label: AppLanguage.english.nativeName, value: LanguageChoice.english),
                        .init(label: AppLanguage.italian.nativeName, value: LanguageChoice.italian)
                    ],
                    selection: $preferences.language,
                    accessibility: L("Language")
                )
            }
            SettingsDivider()
            SettingsRow(title: L("Open on hover"), caption: L("Show the panel when the pointer reaches the notch")) {
                IslandSwitch(isOn: $preferences.openOnHover)
            }
            SettingsDivider()
            SettingsRow(
                title: L("Launch at login"),
                caption: launchAtLoginCaption
            ) {
                IslandSwitch(isOn: launchAtLoginBinding)
            }
            if smartAdd.isAvailable {
                SettingsDivider()
                SettingsRow(
                    title: L("Smart quick add"),
                    caption: L("Understands days, repeats and picks your tags: “domani chiamare mamma”. Runs on this Mac with Apple Intelligence.")
                ) {
                    IslandSwitch(isOn: $preferences.smartAddEnabled)
                }
            }
        }
    }

    private var habitsSection: some View {
        SettingsSection(L("Habits")) {
            if store.habits.isEmpty {
                SettingsHint(L("Add a goal with the repeat button to start a habit. Each one keeps its own streak."))
            } else {
                ForEach(Array(store.habits.enumerated()), id: \.element.id) { index, habit in
                    if index > 0 { SettingsDivider() }
                    HabitSettingsRow(
                        habit: habit,
                        stats: store.habitStats(for: habit.id),
                        scheduleLabel: habit.schedule.label(calendar: store.dateService.currentCalendar)
                    ) {
                        withAnimation(IslandAnimations.defaultSpring) {
                            store.deleteHabit(id: habit.id)
                        }
                    }
                }
            }
        }
    }

    private var tagsSection: some View {
        SettingsSection(L("Tags")) {
            let usage = store.tagUsage
            if usage.isEmpty {
                SettingsHint(L("Type #work in a goal, or add tags from its details. Tap a color to change it."))
            } else {
                ForEach(Array(usage.enumerated()), id: \.element.tag) { index, entry in
                    if index > 0 { SettingsDivider() }
                    TagSettingsRow(
                        tag: entry.tag,
                        count: entry.count,
                        color: TagPalette.color(at: preferences.tagColorIndex(for: entry.tag)),
                        onCycleColor: { preferences.cycleTagColor(entry.tag) },
                        onDelete: {
                            withAnimation(IslandAnimations.defaultSpring) {
                                store.deleteTagEverywhere(entry.tag)
                                preferences.removeTagColor(entry.tag)
                            }
                        }
                    )
                }
            }
        }
    }

    private var aboutFooter: some View {
        HStack {
            Text("One Percent \(Self.versionString)")
                .font(IslandTypography.statCaption)
                .foregroundStyle(IslandPalette.tertiaryText)
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    // MARK: - Pieces

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private var launchAtLoginCaption: String? {
        if let error = launchAtLogin.errorMessage { return error }
        if launchAtLogin.needsApproval { return L("Approve One Percent in System Settings → General → Login Items") }
        return nil
    }

    private static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "v\($0)" } ?? L("dev build")
    }
}

// MARK: - Building blocks

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowText(title)
                .padding(.leading, 2)

            VStack(spacing: 0, content: content)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.rowCornerRadius, style: .continuous)
                        .fill(IslandPalette.restFill)
                )
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(IslandPalette.primaryText)
                if let caption {
                    Text(caption)
                        .font(IslandTypography.statCaption)
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            // Controls keep their natural width; it is the caption that wraps.
            trailing()
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .padding(.vertical, caption == nil ? 0 : 2)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(IslandPalette.hairline)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

struct SettingsHint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(IslandTypography.secondaryMetadata)
            .foregroundStyle(IslandPalette.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Destructive control that asks twice: the first click arms it, the second one confirms.
private struct ConfirmDeleteButton: View {
    var label: String
    var onConfirm: () -> Void

    @State private var isArmed = false
    @State private var token = 0

    var body: some View {
        Button {
            if isArmed {
                onConfirm()
            } else {
                isArmed = true
                token += 1
                let current = token
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if token == current { isArmed = false }
                }
            }
        } label: {
            Group {
                if isArmed {
                    Text(L("Delete?"))
                        .font(IslandTypography.statusLabel)
                        .foregroundStyle(IslandPalette.destructiveAccent)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: IslandMetrics.badgeCornerRadius, style: .continuous)
                                .fill(IslandPalette.destructiveAccent.opacity(0.14))
                        )
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .frame(width: 22, height: 22)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.9))
        .animation(IslandAnimations.hoverFade, value: isArmed)
        .accessibilityLabel(isArmed ? L("Confirm delete %@", label) : L("Delete %@", label))
    }
}

private struct HabitSettingsRow: View {
    let habit: Habit
    let stats: HabitStats
    let scheduleLabel: String
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "repeat")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(IslandPalette.tertiaryText)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(habit.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(IslandPalette.primaryText)
                    .lineLimit(1)
                Text(scheduleLabel)
                    .font(IslandTypography.statCaption)
                    .foregroundStyle(IslandPalette.tertiaryText)
            }

            Spacer(minLength: 6)

            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(stats.currentStreak > 0 ? IslandPalette.streakAccent : IslandPalette.tertiaryText)
                Text("\(stats.currentStreak)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(IslandPalette.primaryText)
            }
            .help(L("Streak %d · best %d", stats.currentStreak, stats.bestStreak))

            ConfirmDeleteButton(label: habit.title, onConfirm: onDelete)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .accessibilityElement(children: .contain)
    }
}

private struct TagSettingsRow: View {
    let tag: String
    let count: Int
    let color: Color
    var onCycleColor: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCycleColor) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.8))
            .help(L("Change color"))
            .accessibilityLabel(L("Change color of %@", tag))

            Text(tag)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(IslandPalette.primaryText)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(Lp("%d goal", "%d goals", count))
                .font(IslandTypography.statCaption)
                .foregroundStyle(IslandPalette.tertiaryText)

            ConfirmDeleteButton(label: tag, onConfirm: onDelete)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
    }
}

/// Notifications master switch plus the per-slot times. Observes the coordinator so the
/// "blocked in System Settings" notice appears as soon as permission changes.
private struct RemindersSettingsSection: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var reminders: ReminderCoordinator

    var body: some View {
        SettingsSection(L("Reminders")) {
            SettingsRow(title: L("Gentle notifications"), caption: L("A short nudge, no sound")) {
                IslandSwitch(isOn: notificationsBinding)
            }

            if preferences.notificationsEnabled {
                if reminders.authorization == .denied {
                    SettingsDivider()
                    permissionNotice
                }
                SettingsDivider()
                reminderRow(L("Morning plan"), slot: $preferences.morning)
                SettingsDivider()
                reminderRow(L("Afternoon check-in"), slot: $preferences.afternoon)
                SettingsDivider()
                SettingsRow(title: L("Evening wrap-up"), caption: L("Uses the wrap-up time above")) {
                    IslandSwitch(isOn: $preferences.wrapUp.isEnabled)
                }
            }
        }
        .onAppear {
            Task { await reminders.refreshAuthorization() }
        }
    }

    private func reminderRow(_ title: String, slot: Binding<AppPreferences.ReminderSlot>) -> some View {
        SettingsRow(title: title) {
            HStack(spacing: 10) {
                TimeStepperView(minutes: slot.minutes, isEnabled: slot.wrappedValue.isEnabled)
                IslandSwitch(isOn: slot.isEnabled)
            }
        }
    }

    private var permissionNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(IslandPalette.inProgressAccent)
            Text(L("Notifications are blocked for One Percent."))
                .font(IslandTypography.secondaryMetadata)
                .foregroundStyle(IslandPalette.secondaryText)
            Spacer(minLength: 4)
            Button(L("Open Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(IslandTypography.statusLabel)
            .foregroundStyle(IslandPalette.completedAccent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { preferences.notificationsEnabled },
            set: { enabled in
                preferences.notificationsEnabled = enabled
                if enabled {
                    Task { await reminders.requestAuthorization() }
                }
            }
        )
    }
}

private struct DisplayChoiceRow: View {
    let title: String
    let caption: String
    let isSelected: Bool
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? IslandPalette.completedAccent : IslandPalette.tertiaryText, lineWidth: 1.4)
                    Circle()
                        .fill(IslandPalette.completedAccent)
                        .padding(3.5)
                        .scaleEffect(isSelected ? 1 : 0.3)
                        .opacity(isSelected ? 1 : 0)
                }
                .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(IslandTypography.statusLabel)
                        .foregroundStyle(IslandPalette.primaryText)
                        .lineLimit(1)
                    Text(caption)
                        .font(IslandTypography.statCaption)
                        .foregroundStyle(IslandPalette.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(isHovered ? IslandPalette.restFill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
        .animation(IslandAnimations.checkSpring, value: isSelected)
        .accessibilityLabel("\(title). \(caption)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
