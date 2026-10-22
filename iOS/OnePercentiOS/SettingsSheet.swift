import SwiftUI
import OnePercentCore

/// Language, the cloud account, habits and tags.
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                if let cloud = model.cloud {
                    CloudSettingsSection(cloud: cloud, calendar: store.dateService.currentCalendar)
                }

                RemindersSection(reminders: model.reminders, calendar: store.dateService.currentCalendar)

                FocusSection(settings: model.focusSettings, alerts: model.focusAlerts)

                SignatureSection(watch: model.signature, calendar: store.dateService.currentCalendar)
                    .id("signature")

                Section(L("Language")) {
                    HStack(spacing: 8) {
                        ChoiceChip(title: L("System"), isSelected: model.language == .system) { model.language = .system }
                        ChoiceChip(title: AppLanguage.english.nativeName, isSelected: model.language == .english) { model.language = .english }
                        ChoiceChip(title: AppLanguage.italian.nativeName, isSelected: model.language == .italian) { model.language = .italian }
                    }
                    .listRowBackground(Theme.surface)
                }

                Section(L("Habits")) {
                    if store.habits.isEmpty {
                        Text(L("Add a goal with the repeat button to start a habit. Each one keeps its own streak."))
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Theme.tertiaryText)
                            .listRowBackground(Theme.surface)
                    }
                    ForEach(store.habits) { habit in
                        NavigationLink {
                            HabitEditor(store: store, habitID: habit.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(habit.title).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(Theme.primaryText)
                                    Text(habit.schedule.label(calendar: store.dateService.currentCalendar))
                                        .font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.tertiaryText)
                                }
                                Spacer()
                                let streak = store.habitStats(for: habit.id).currentStreak
                                if streak > 0 { Chip(text: "\(streak)", systemImage: "flame.fill", tint: Theme.orange) }
                            }
                        }
                        .listRowBackground(Theme.surface)
                    }
                }

                Section(L("Tags")) {
                    let usage = store.tagUsage
                    if usage.isEmpty {
                        Text(L("Type #work in a goal, or add tags from its details. Tap a color to change it."))
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Theme.tertiaryText)
                            .listRowBackground(Theme.surface)
                    }
                    ForEach(usage, id: \.tag) { entry in
                        HStack(spacing: 12) {
                            Button { model.cycleTagColor(entry.tag) } label: {
                                Circle().fill(model.tagColor(entry.tag)).frame(width: 22, height: 22)
                                    .frame(width: 40, height: 40).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L("Change color of %@", entry.tag))
                            Text(entry.tag).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(Theme.primaryText)
                            Spacer()
                            Text("\(entry.count)").font(.system(size: 14, design: .rounded)).monospacedDigit().foregroundStyle(Theme.tertiaryText)
                        }
                        .listRowBackground(Theme.surface)
                        .swipeActions {
                            Button(role: .destructive) {
                                withAnimation { store.deleteTagEverywhere(entry.tag); model.forgetTagColor(entry.tag) }
                            } label: { Label(L("Delete"), systemImage: "trash") }
                        }
                    }
                }

                Section {
                    Text("One Percent \(Self.versionString)")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.tertiaryText)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            #if DEBUG
            // `-demoScrollSignature` opens Settings already scrolled to the signature row, for screenshots.
            .onAppear {
                guard ProcessInfo.processInfo.arguments.contains("-demoScrollSignature") else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo("signature", anchor: .center) }
            }
            #endif
            }
            .navigationTitle(L("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }.foregroundStyle(Theme.mint)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
    }

    private static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "v\($0)" } ?? L("dev build")
    }
}

/// The weekdays of one habit, and a way to stop it.
struct HabitEditor: View {
    @ObservedObject var store: TaskStore
    let habitID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<Int> = []
    @State private var loaded = false
    @State private var confirmStop = false

    private var habit: Habit? { store.habits.first { $0.id == habitID } }

    var body: some View {
        Group {
            if let habit {
                List {
                    Section {
                        WeekdayToggles(calendar: store.dateService.currentCalendar, selection: $days)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    } header: {
                        Text(L("Tap days to turn them on or off"))
                    }
                    Section {
                        Button(role: .destructive) { confirmStop = true } label: {
                            Text(L("Delete goal")).foregroundStyle(Theme.destructive)
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .navigationTitle(habit.title)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    if !loaded { days = habit.schedule.selectedDays; loaded = true }
                }
                .onChange(of: days) { _, newDays in
                    guard loaded else { return }
                    store.updateHabitSchedule(id: habitID, schedule: .custom(days: Array(newDays)))
                }
                .confirmationDialog(L("Delete?"), isPresented: $confirmStop, titleVisibility: .visible) {
                    Button(L("Delete goal"), role: .destructive) {
                        store.deleteHabit(id: habitID)
                        dismiss()
                    }
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
    }
}

/// Sign in or out of the sync account.
struct CloudSettingsSection: View {
    @ObservedObject var cloud: CloudSyncController
    let calendar: Calendar

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        Section(L("Cloud sync")) {
            switch cloud.account {
            case .signedOut, .signingIn:
                form
            case .signedIn(let account):
                VStack(alignment: .leading, spacing: 4) {
                    Text(account).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(Theme.primaryText)
                    Text(statusText).font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.tertiaryText)
                }
                .listRowBackground(Theme.surface)
                Button(L("Sync now")) { Task { await cloud.syncNow() } }
                    .foregroundStyle(Theme.mint)
                    .disabled(cloud.status == .syncing)
                    .listRowBackground(Theme.surface)
                Button(L("Sign out")) { Task { await cloud.signOut() } }
                    .foregroundStyle(Theme.destructive)
                    .listRowBackground(Theme.surface)
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        let isSigningIn = cloud.account == .signingIn
        let canSubmit = !isSigningIn && email.contains("@") && !password.isEmpty

        Text(L("Keep your goals and habits in step with your other devices."))
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(Theme.secondaryText)
            .listRowBackground(Theme.surface)

        TextField("", text: $email, prompt: Text(L("Email")).foregroundStyle(Theme.tertiaryText))
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: .email)
            .submitLabel(.next)
            .onSubmit { focus = .password }
            .listRowBackground(Theme.surface)

        SecureField("", text: $password, prompt: Text(L("Password")).foregroundStyle(Theme.tertiaryText))
            .textContentType(.password)
            .focused($focus, equals: .password)
            .submitLabel(.go)
            .onSubmit { submit(canSubmit) }
            .listRowBackground(Theme.surface)

        Button(isSigningIn ? L("Signing in…") : L("Sign in")) { submit(canSubmit) }
            .foregroundStyle(canSubmit ? Theme.mint : Theme.tertiaryText)
            .disabled(!canSubmit)
            .listRowBackground(Theme.surface)

        if let failure = cloud.signInFailure {
            Text(message(for: failure))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.destructive)
                .listRowBackground(Theme.surface)
        }

        Text(L("The first sign-in merges what is on this iPhone with the cloud. Nothing is deleted."))
            .font(.system(size: 12, design: .rounded))
            .foregroundStyle(Theme.tertiaryText)
            .listRowBackground(Theme.surface)
    }

    private func submit(_ allowed: Bool) {
        guard allowed else { return }
        let typedEmail = email, typedPassword = password
        focus = nil
        Task {
            await cloud.signIn(email: typedEmail, password: typedPassword)
            if case .signedIn = cloud.account { password = "" }
        }
    }

    private func message(for failure: CloudSyncController.SignInFailure) -> String {
        switch failure {
        case .wrongCredentials: return L("Wrong email or password.")
        case .emailNotConfirmed: return L("Confirm your email first: check your inbox.")
        case .offline: return L("No connection. Try again in a moment.")
        case .other(let detail): return L("Couldn't sign in: %@", detail)
        }
    }

    private var statusText: String {
        var text: String
        switch cloud.status {
        case .idle: text = L("Starting…")
        case .syncing: text = L("Syncing…")
        case .synced(let date): text = L("Synced at %@", LocalizedDates.string(date, template: "jm", calendar: calendar))
        case .offline: text = L("Offline. It will retry by itself.")
        case .signedOut: text = L("The session ended. Sign in again.")
        case .failed(let detail): text = L("Sync problem: %@", detail)
        }
        if cloud.unreadableRecords > 0 {
            text += " " + Lp("%d item needs a newer version of One Percent.", "%d items need a newer version of One Percent.", cloud.unreadableRecords)
        }
        return text
    }
}

/// Morning, afternoon and evening nudges.
struct RemindersSection: View {
    @ObservedObject var reminders: PhoneReminders
    let calendar: Calendar

    var body: some View {
        Section(L("Reminders")) {
            Toggle(L("Gentle notifications"), isOn: Binding(
                get: { reminders.isEnabled },
                set: { value in Task { await reminders.setEnabled(value) } }
            ))
            .tint(Theme.mint)
            .listRowBackground(Theme.surface)

            if reminders.isBlocked {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Notifications are blocked for One Percent."))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.tertiaryText)
                    Button(L("Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .foregroundStyle(Theme.mint)
                }
                .listRowBackground(Theme.surface)
            }

            if reminders.isEnabled {
                row(L("Morning plan"), kind: .morning)
                row(L("Afternoon check-in"), kind: .afternoon)
                row(L("Evening wrap-up"), kind: .wrapUp)
            }
        }
    }

    private func row(_ title: String, kind: ReminderKind) -> some View {
        let slot = reminders.slot(kind)
        return HStack {
            Toggle(title, isOn: Binding(
                get: { slot.isEnabled },
                set: { reminders.setSlot(kind, .init(isEnabled: $0, minutes: slot.minutes)) }
            ))
            .tint(Theme.mint)

            if slot.isEnabled {
                DatePicker("", selection: Binding(
                    get: { date(for: slot.minutes) },
                    set: { reminders.setSlot(kind, .init(isEnabled: true, minutes: minutes(of: $0))) }
                ), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .fixedSize()
            }
        }
        .listRowBackground(Theme.surface)
    }

    private func date(for minutes: Int) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    private func minutes(of date: Date) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}

/// How long this copy of the app keeps opening. Only shown for a copy signed with a free Apple ID.
struct SignatureSection: View {
    @ObservedObject var watch: SignatureWatch
    let calendar: Calendar

    var body: some View {
        if let expires = watch.expires, let days = watch.daysLeft {
            Section(L("App signature")) {
                HStack {
                    Text(L("Valid until"))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(LocalizedDates.string(expires, template: "EEEMMMdjm", calendar: calendar))
                            .foregroundStyle(Theme.secondaryText)
                        Text(remaining(days: days, expires: expires))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(watch.isClose ? Theme.orange : Theme.tertiaryText)
                    }
                }
                .listRowBackground(Theme.surface)

                Toggle(L("Warn me the evening before"), isOn: $watch.warnsBefore)
                    .tint(Theme.mint)
                    .listRowBackground(Theme.surface)

                Text(L("A free Apple ID signs the app for 7 days. The Mac renews it by itself while it is on and the iPhone is on the same Wi-Fi. Your goals are safe in the cloud either way."))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.tertiaryText)
                    .listRowBackground(Theme.surface)
            }
        }
    }

    private func remaining(days: Int, expires: Date) -> String {
        if SigningExpiryPlanner.hasExpired(expires: expires, now: Date()) { return L("Expired") }
        if days == 0 { return L("Today") }
        return Lp("%d day left", "%d days left", days)
    }
}

/// The timer's Pomodoro mode: block lengths, breaks and the alert when a block ends.
struct FocusSection: View {
    @ObservedObject var settings: PhoneFocusSettings
    let alerts: FocusBackgroundAlerts

    var body: some View {
        Section(L("Focus")) {
            Toggle(isOn: $settings.pomodoroEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Pomodoro")).font(.system(size: 16, weight: .medium, design: .rounded))
                    Text(L("Timed blocks with breaks, instead of a free stopwatch"))
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.tertiaryText)
                }
            }
            .tint(Theme.mint)
            .listRowBackground(Theme.surface)

            if settings.pomodoroEnabled {
                stepper(L("Focus block"), value: $settings.focusMinutes, range: 5...120, step: 5)
                stepper(L("Short break"), value: $settings.shortBreakMinutes, range: 1...30, step: 1)
                stepper(L("Long break"), value: $settings.longBreakMinutes, range: 5...60, step: 5)
                Stepper(value: $settings.pomodoroRounds, in: 2...8) {
                    HStack {
                        Text(L("Blocks per round"))
                        Spacer()
                        Text("\(settings.pomodoroRounds)").monospacedDigit().foregroundStyle(Theme.secondaryText)
                    }
                }
                .listRowBackground(Theme.surface)

                Toggle(L("Notification when a block ends"), isOn: Binding(
                    get: { settings.focusNotifications },
                    set: { value in
                        if value {
                            Task { settings.focusNotifications = await alerts.requestAuthorization() }
                        } else {
                            settings.focusNotifications = false
                        }
                    }
                ))
                .tint(Theme.mint)
                .listRowBackground(Theme.surface)
            }
        }
    }

    private func stepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value.wrappedValue) min").monospacedDigit().foregroundStyle(Theme.secondaryText)
            }
        }
        .listRowBackground(Theme.surface)
    }
}
