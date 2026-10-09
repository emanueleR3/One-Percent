import Foundation
import Combine

/// The signed-in account and the sync that runs for it. What Settings shows and drives.
@MainActor
public final class CloudSyncController: ObservableObject {
    public enum Account: Equatable, Sendable {
        case signedOut
        case signingIn
        case signedIn(email: String)
    }

    public enum SignInFailure: Equatable, Sendable {
        case wrongCredentials
        case emailNotConfirmed
        case offline
        case other(String)
    }

    @Published public private(set) var account: Account = .signedOut
    @Published public private(set) var signInFailure: SignInFailure?
    @Published public private(set) var status: SyncEngine.Status = .idle
    @Published public private(set) var unreadableRecords = 0

    private let auth: SupabaseAuth
    private let engine: SyncEngine
    private let realtime: SupabaseRealtime?
    private let beforeFirstSync: () -> Void
    private var cancellables = Set<AnyCancellable>()

    /// `beforeFirstSync` runs once per sign-in, before this device merges with the cloud (the app
    /// uses it to copy its files).
    public init(
        auth: SupabaseAuth,
        engine: SyncEngine,
        realtime: SupabaseRealtime? = nil,
        beforeFirstSync: @escaping () -> Void = {}
    ) {
        self.auth = auth
        self.engine = engine
        self.realtime = realtime
        self.beforeFirstSync = beforeFirstSync

        engine.$status
            .sink { [weak self] status in
                guard let self else { return }
                self.status = status
                // The server stopped accepting this device's session: ask for a new sign-in.
                if status == .signedOut, case .signedIn = self.account {
                    self.engine.stop()
                    self.account = .signedOut
                }
            }
            .store(in: &cancellables)
        engine.$unreadableRecords
            .sink { [weak self] in self?.unreadableRecords = $0 }
            .store(in: &cancellables)
    }

    /// Picks up where the last run left off: a saved session starts syncing at once.
    public func start() async {
        guard case .signedOut = account, let session = await auth.currentSession() else { return }
        account = .signedIn(email: session.email)
        engine.start(nudges: realtime?.nudges())
    }

    public func signIn(email: String, password: String) async {
        if case .signingIn = account { return }
        account = .signingIn
        signInFailure = nil
        do {
            let session = try await auth.signIn(email: email, password: password)
            beforeFirstSync()
            account = .signedIn(email: session.email)
            engine.start(nudges: realtime?.nudges())
        } catch let error as AuthError {
            account = .signedOut
            switch error {
            case .invalidCredentials: signInFailure = .wrongCredentials
            case .emailNotConfirmed: signInFailure = .emailNotConfirmed
            case .offline: signInFailure = .offline
            case .server(let status, let message): signInFailure = .other("\(status): \(message)")
            }
        } catch {
            account = .signedOut
            signInFailure = .other(error.localizedDescription)
        }
    }

    /// Stops syncing and forgets the session. Goals and habits on this device stay.
    public func signOut() async {
        engine.stop()
        engine.reset()
        await auth.signOut()
        account = .signedOut
        signInFailure = nil
    }

    public func syncNow() async {
        guard case .signedIn = account else { return }
        await engine.syncNow()
    }
}
