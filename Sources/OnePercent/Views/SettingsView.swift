import SwiftUI
import AppKit

/// Preferences page: wrap-up, reminders, general behaviour, habits and tags.
struct SettingsView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    @ObservedObject var smartAdd: SmartAddService
    let reminders: ReminderCoordinator?

    var body: some View {
        FadingScrollView {
            VStack(alignment: .leading, spacing: 14) {
                wrapUpSection
                remindersSection
                generalSection
                habitsSection
                tagsSection
                aboutFooter
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .onAppear { launchAtLogin.refresh() }
    }

    // MARK: - Sections

    private var wrapUpSection: some View {
        SettingsSection("Day wrap-up") {
            SettingsRow(title: "Offer to move what's left", caption: "A prompt in the panel after this time") {
                IslandSwitch(isOn: $preferences.wrapUp.isEnabled)
            }
            SettingsDivider()
            SettingsRow(title: "After") {
                TimeStepperView(minutes: $preferences.wrapUp.minutes, isEnabled: preferences.wrapUp.isEnabled)
            }
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        if let reminders {
            RemindersSettingsSection(preferences: preferences, reminders: reminders)
        } else {
            SettingsSection("Reminders") {
                SettingsRow(title: "Gentle notifications", caption: "Available in the installed app") {
                    IslandSwitch(isOn: .constant(false))
                        .opacity(0.4)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var generalSection: some View {
        SettingsSection("General") {
            SettingsRow(title: "Open on hover", caption: "Show the panel when the pointer reaches the notch") {
                IslandSwitch(isOn: $preferences.openOnHover)
            }
            SettingsDivider()
            SettingsRow(
                title: "Launch at login",
                caption: launchAtLoginCaption
            ) {
                IslandSwitch(isOn: launchAtLoginBinding)
            }
            if smartAdd.isAvailable {
                SettingsDivider()
                SettingsRow(
                    title: "Smart quick add",
                    caption: "Understands days, repeats and picks your tags: “domani chiamare mamma”. Runs on this Mac with Apple Intelligence."
                ) {
                    IslandSwitch(isOn: $preferences.smartAddEnabled)
                }
            }
        }
    }

    private var habitsSection: some View {
        SettingsSection("Habits") {
            if store.habits.isEmpty {
                SettingsHint("Add a goal with the repeat button to start a habit. Each one keeps its own streak.")
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
        SettingsSection("Tags") {
            let usage = store.tagUsage
            if usage.isEmpty {
                SettingsHint("Type #work in a goal, or add tags from its details. Tap a color to change it.")
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
        if launchAtLogin.needsApproval { return "Approve One Percent in System Settings → General → Login Items" }
        return nil
    }

    private static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "v\($0)" } ?? "dev build"
    }
}

// MARK: - Building blocks

private struct SettingsSection<Content: View>: View {
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

private struct SettingsRow<Trailing: View>: View {
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
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .padding(.vertical, caption == nil ? 0 : 2)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(IslandPalette.hairline)
            .frame(height: 1)
            .padding(.leading, 12)
    }
}

private struct SettingsHint: View {
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
                    Text("Delete?")
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
        .accessibilityLabel(isArmed ? "Confirm delete \(label)" : "Delete \(label)")
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
            .help("Streak \(stats.currentStreak) · best \(stats.bestStreak)")

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
            .help("Change color")
            .accessibilityLabel("Change color of \(tag)")

            Text(tag)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(IslandPalette.primaryText)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(count == 1 ? "1 goal" : "\(count) goals")
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
        SettingsSection("Reminders") {
            SettingsRow(title: "Gentle notifications", caption: "A short nudge, no sound") {
                IslandSwitch(isOn: notificationsBinding)
            }

            if preferences.notificationsEnabled {
                if reminders.authorization == .denied {
                    SettingsDivider()
                    permissionNotice
                }
                SettingsDivider()
                reminderRow("Morning plan", slot: $preferences.morning)
                SettingsDivider()
                reminderRow("Afternoon check-in", slot: $preferences.afternoon)
                SettingsDivider()
                SettingsRow(title: "Evening wrap-up", caption: "Uses the wrap-up time above") {
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
            Text("Notifications are blocked for One Percent.")
                .font(IslandTypography.secondaryMetadata)
                .foregroundStyle(IslandPalette.secondaryText)
            Spacer(minLength: 4)
            Button("Open Settings") {
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
