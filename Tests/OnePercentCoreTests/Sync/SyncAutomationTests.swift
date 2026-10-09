import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

@MainActor
final class SyncAutomationTests: XCTestCase {
    private var server: FakeSyncServer!
    private var mac: Device!
    private var phone: Device!

    override func setUp() async throws {
        server = FakeSyncServer()
        mac = Device("mac", server: server)
        phone = Device("phone", server: server)
    }

    override func tearDown() async throws {
        mac.engine.stop()
        phone.engine.stop()
    }

    private func eventually(_ seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    func testStartSyncsAtOnceAndThenFollowsLocalChanges() async {
        mac.add("Before start")
        mac.engine.start(debounce: 0.05, interval: 30)
        phone.engine.start(debounce: 0.05, interval: 0.2)

        let first = await eventually { self.phone.titles() == ["Before start"] }
        XCTAssertTrue(first, "starting syncs right away")

        mac.add("After start")
        let second = await eventually { Set(self.phone.titles()) == ["Before start", "After start"] }
        XCTAssertTrue(second, "a change made later travels on its own")
    }

    func testAChangeIsPushedShortlyAfterItIsMade() async {
        mac.engine.start(debounce: 0.05, interval: 60)
        _ = await eventually { self.mac.engine.status.isSynced }
        mac.add("Quick")
        let pushed = await eventually { self.server.storedRecords.contains { $0.kind == .task } }
        XCTAssertTrue(pushed, "no need to wait for the timer")
    }

    func testABurstOfEditsIsSentTogetherNotOneByOne() async {
        mac.engine.start(debounce: 0.2, interval: 60)
        _ = await eventually { self.mac.engine.status.isSynced }
        server.resetCounters()
        for index in 0..<25 { mac.add("Goal \(index)") }
        _ = await eventually { self.server.storedRecords.count >= 25 }
        XCTAssertLessThanOrEqual(server.pushCalls, 2, "edits close together share a round trip")
    }

    func testALiveNudgeMakesTheOtherDevicePullImmediately() async {
        var continuation: AsyncStream<Void>.Continuation!
        let nudges = AsyncStream<Void> { continuation = $0 }
        phone.engine.start(debounce: 0.05, interval: 60, nudges: nudges)
        _ = await eventually { self.phone.engine.status.isSynced }

        mac.add("Pushed from the Mac")
        await mac.sync()
        XCTAssertTrue(phone.titles().isEmpty, "the long timer alone would not have noticed yet")

        continuation.yield()
        let arrived = await eventually { self.phone.titles() == ["Pushed from the Mac"] }
        XCTAssertTrue(arrived)
    }

    func testStopEndsTheAutomaticSyncing() async {
        mac.engine.start(debounce: 0.05, interval: 0.1)
        _ = await eventually { self.mac.engine.status.isSynced }
        mac.engine.stop()
        server.resetCounters()
        mac.add("Added after stop")
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(server.pushedRecords, 0)
    }

    func testFailuresBackOffInsteadOfHammeringTheServer() async {
        server.failure = .offline
        mac.engine.start(debounce: 0.05, interval: 0.05)
        try? await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(mac.engine.status, .offline)
        server.failure = nil
        XCTAssertTrue(mac.engine.status != .syncing)
    }
}
