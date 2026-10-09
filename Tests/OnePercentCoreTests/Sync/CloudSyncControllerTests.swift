import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

@MainActor
final class CloudSyncControllerTests: XCTestCase {
    private let config = SupabaseConfig(url: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test")
    private var server: FakeSyncServer!
    private var device: Device!
    private var backups = 0

    override func setUp() async throws {
        server = FakeSyncServer()
        device = Device("mac", server: server)
        backups = 0
    }

    private func makeController(http: StubHTTP, secrets: SecretStoring = InMemorySecretStore()) -> CloudSyncController {
        let auth = SupabaseAuth(config: config, secrets: secrets, http: http)
        return CloudSyncController(auth: auth, engine: device.engine, beforeFirstSync: { [unowned self] in self.backups += 1 })
    }

    private func eventually(_ seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    func testSigningInBacksUpThenStartsSyncing() async {
        device.add("Existing goal")
        let cloud = makeController(http: StubHTTP { _ in (tokenResponse(), 200) })

        await cloud.signIn(email: "me@example.com", password: "pw")

        XCTAssertEqual(cloud.account, .signedIn(email: "me@example.com"))
        XCTAssertEqual(backups, 1, "files are copied before the first merge")
        XCTAssertNil(cloud.signInFailure)
        let uploaded = await eventually { self.server.storedRecords.count == 1 }
        XCTAssertTrue(uploaded, "what was on this device goes up")
        device.engine.stop()
    }

    func testAWrongPasswordStaysSignedOutAndTouchesNothing() async {
        device.add("Local only")
        let cloud = makeController(http: StubHTTP { _ in (json(["error_code": "invalid_credentials", "msg": "Invalid login credentials"]), 400) })

        await cloud.signIn(email: "me@example.com", password: "bad")

        XCTAssertEqual(cloud.account, .signedOut)
        XCTAssertEqual(cloud.signInFailure, .wrongCredentials)
        XCTAssertEqual(backups, 0)
        XCTAssertTrue(server.storedRecords.isEmpty)
        XCTAssertEqual(device.titles(), ["Local only"])
    }

    func testOtherSignInProblemsAreTold() async {
        let unconfirmed = makeController(http: StubHTTP { _ in (json(["error_code": "email_not_confirmed", "msg": "x"]), 400) })
        await unconfirmed.signIn(email: "a@b.c", password: "x")
        XCTAssertEqual(unconfirmed.signInFailure, .emailNotConfirmed)

        let offline = makeController(http: StubHTTP { _ in throw URLError(.notConnectedToInternet) })
        await offline.signIn(email: "a@b.c", password: "x")
        XCTAssertEqual(offline.signInFailure, .offline)

        let broken = makeController(http: StubHTTP { _ in (json(["message": "boom"]), 500) })
        await broken.signIn(email: "a@b.c", password: "x")
        XCTAssertEqual(broken.signInFailure, .other("500: boom"))
    }

    func testASavedSessionResumesSyncingAtLaunch() async throws {
        let secrets = InMemorySecretStore()
        let first = makeController(http: StubHTTP { _ in (tokenResponse(), 200) }, secrets: secrets)
        await first.signIn(email: "me@example.com", password: "pw")
        device.engine.stop()

        // A new launch: same saved session, nothing typed.
        let reopened = makeController(http: StubHTTP { _ in XCTFail("no sign-in needed"); return (Data(), 500) }, secrets: secrets)
        XCTAssertEqual(reopened.account, .signedOut)
        await reopened.start()
        XCTAssertEqual(reopened.account, .signedIn(email: "me@example.com"))
        XCTAssertEqual(backups, 1, "resuming is not a new sign-in, so no new backup")
        device.engine.stop()
    }

    func testStartWithoutASessionDoesNothing() async {
        let cloud = makeController(http: StubHTTP { _ in XCTFail(); return (Data(), 500) })
        await cloud.start()
        XCTAssertEqual(cloud.account, .signedOut)
        XCTAssertEqual(server.pulledRecords, 0)
    }

    func testSigningOutStopsSyncingForgetsTheSessionAndKeepsTheGoals() async {
        let secrets = InMemorySecretStore()
        let cloud = makeController(http: StubHTTP { _ in (tokenResponse(), 200) }, secrets: secrets)
        device.add("Mine")
        await cloud.signIn(email: "me@example.com", password: "pw")
        _ = await eventually { self.server.storedRecords.count == 1 }

        await cloud.signOut()

        XCTAssertEqual(cloud.account, .signedOut)
        XCTAssertNil(secrets.read("session"))
        XCTAssertEqual(device.titles(), ["Mine"], "local goals stay")
        XCTAssertEqual(device.statePersistence.stored?.known.count, 0, "the sync memory is cleared")

        server.resetCounters()
        device.add("After sign-out")
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(server.pushedRecords, 0, "nothing is sent any more")
    }

    func testARevokedSessionTurnsIntoASignedOutAccount() async {
        let cloud = makeController(http: StubHTTP { _ in (tokenResponse(), 200) })
        await cloud.signIn(email: "me@example.com", password: "pw")
        server.failure = .notSignedIn
        await device.engine.syncNow()
        let flipped = await eventually { cloud.account == .signedOut }
        XCTAssertTrue(flipped, "the form comes back so the user can sign in again")
        XCTAssertEqual(cloud.status, .signedOut)
        server.failure = nil
        device.engine.stop()
    }

    func testStatusMirrorsTheEngine() async {
        let cloud = makeController(http: StubHTTP { _ in (tokenResponse(), 200) })
        await cloud.signIn(email: "me@example.com", password: "pw")
        let synced = await eventually { cloud.status.isSynced }
        XCTAssertTrue(synced)
        device.engine.stop()
    }

    func testSyncNowDoesNothingWhenSignedOut() async {
        let cloud = makeController(http: StubHTTP { _ in (Data(), 500) })
        await cloud.syncNow()
        XCTAssertEqual(server.pulledRecords, 0)
    }
}

final class SyncSupportFilesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("op-sync-support-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testFileSecretStoreRoundTripsAndIsPrivate() throws {
        let url = folder.appendingPathComponent("session.json")
        let store = FileSecretStore(fileURL: url)
        XCTAssertNil(store.read("session"))

        store.write(Data("token".utf8), account: "session")
        store.write(Data("other".utf8), account: "second")
        XCTAssertEqual(store.read("session"), Data("token".utf8))
        XCTAssertEqual(FileSecretStore(fileURL: url).read("second"), Data("other".utf8), "survives a new instance")

        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600, "readable only by the user")

        store.delete("session")
        XCTAssertNil(store.read("session"))
        store.delete("second")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the file goes away with its last secret")
    }

    func testBackupCopiesBothFilesAndKeepsOnlyTheNewest() throws {
        try Data("[tasks]".utf8).write(to: folder.appendingPathComponent("tasks.json"))
        try Data("[habits]".utf8).write(to: folder.appendingPathComponent("habits.json"))

        var made: [URL] = []
        for minute in 0..<7 {
            let url = try XCTUnwrap(SyncBackup.make(storage: folder, now: Date(timeIntervalSince1970: 1_800_000_000 + Double(minute) * 60)))
            made.append(url)
        }
        XCTAssertEqual(try String(contentsOf: made[6].appendingPathComponent("tasks.json")), "[tasks]")
        XCTAssertEqual(try String(contentsOf: made[6].appendingPathComponent("habits.json")), "[habits]")

        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(SyncBackup.folderName).path)
        XCTAssertEqual(kept.count, SyncBackup.keep)
        XCTAssertFalse(kept.contains(made[0].lastPathComponent), "the oldest are forgotten")
        XCTAssertTrue(kept.contains(made[6].lastPathComponent))
    }

    func testBackupWithNothingToCopyDoesNothing() {
        XCTAssertNil(SyncBackup.make(storage: folder))
    }

    func testTwoBackupsInTheSameSecondDoNotOverwriteEachOther() throws {
        try Data("x".utf8).write(to: folder.appendingPathComponent("tasks.json"))
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try XCTUnwrap(SyncBackup.make(storage: folder, now: moment))
        let second = try XCTUnwrap(SyncBackup.make(storage: folder, now: moment))
        XCTAssertNotEqual(first, second)
    }
}
