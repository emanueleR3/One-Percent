import SwiftUI
import OnePercentCore

/// Settings → Cloud sync: sign in once and the goals and habits follow you to the other devices.
struct CloudSyncSection: View {
    @ObservedObject var cloud: CloudSyncController
    let calendar: Calendar
    @Binding var isTyping: Bool

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        SettingsSection(L("Cloud sync")) {
            switch cloud.account {
            case .signedOut, .signingIn:
                signInForm
            case .signedIn(let account):
                signedIn(as: account)
            }
        }
        .onChange(of: focus) { _, field in isTyping = field != nil }
        .onDisappear { isTyping = false }
    }

    // MARK: Signed out

    private var signInForm: some View {
        let isSigningIn = cloud.account == .signingIn
        let canSubmit = !isSigningIn && email.contains("@") && !password.isEmpty

        return VStack(alignment: .leading, spacing: 8) {
            Text(L("Keep your goals and habits in step with your other devices."))
                .font(IslandTypography.secondaryMetadata)
                .foregroundStyle(IslandPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            TextField("", text: $email, prompt: Text(L("Email")).foregroundStyle(IslandPalette.tertiaryText))
                .textContentType(.username)
                .focused($focus, equals: .email)
                .onSubmit { focus = .password }
                .modifier(CloudFieldStyle())

            SecureField("", text: $password, prompt: Text(L("Password")).foregroundStyle(IslandPalette.tertiaryText))
                .textContentType(.password)
                .focused($focus, equals: .password)
                .onSubmit { submit(canSubmit) }
                .modifier(CloudFieldStyle())

            HStack(spacing: 8) {
                CloudActionButton(title: isSigningIn ? L("Signing in…") : L("Sign in"), isProminent: true, isEnabled: canSubmit) {
                    submit(canSubmit)
                }
                if let failure = cloud.signInFailure {
                    Text(message(for: failure))
                        .font(IslandTypography.statCaption)
                        .foregroundStyle(IslandPalette.deferredAccent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(L("The first sign-in merges what is on this Mac with the cloud. Nothing is deleted, and a backup is kept."))
                .font(IslandTypography.statCaption)
                .foregroundStyle(IslandPalette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
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

    // MARK: Signed in

    private func signedIn(as account: String) -> some View {
        VStack(spacing: 0) {
            SettingsRow(title: account, caption: statusText) {
                CloudActionButton(title: L("Sync now"), isEnabled: cloud.status != .syncing) {
                    Task { await cloud.syncNow() }
                }
            }
            SettingsDivider()
            SettingsRow(title: L("Sign out"), caption: L("This Mac keeps its goals and habits.")) {
                CloudActionButton(title: L("Sign out")) {
                    Task { await cloud.signOut() }
                }
            }
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

private struct CloudFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(IslandPalette.primaryText)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                    .fill(IslandPalette.hoverFill)
            )
    }
}

private struct CloudActionButton: View {
    let title: String
    var isProminent = false
    var isEnabled = true
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isProminent ? IslandPalette.completedAccent : IslandPalette.primaryText)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: IslandMetrics.controlCornerRadius, style: .continuous)
                        .fill(isProminent
                              ? IslandPalette.completedAccent.opacity(isHovered ? 0.24 : 0.16)
                              : (isHovered ? IslandPalette.hoverFill : IslandPalette.restFill))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovered = $0 }
        .animation(IslandAnimations.hoverFade, value: isHovered)
    }
}
