import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

/// Plays the part of Supabase's REST API on top of `FakeSyncServer`: the same URLs, the same JSON
/// shapes, Postgres-style timestamps (`+00:00`, trailing zeros trimmed) and jsonb's habit of
/// re-writing the JSON it stores. Everything between the engine and the wire is the real code.
final class SupabaseHTTPEmulator: HTTPSending, @unchecked Sendable {
    let backend = FakeSyncServer()

    private func postgresStamp(_ date: Date) -> String {
        var text = WireDate.string(date)            // 2027-01-15T08:00:00.500000Z
        text.removeLast()                            // Z
        while text.hasSuffix("0"), text.contains(".") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "+00:00"
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        func reply(_ object: Any, _ status: Int = 200) throws -> (Data, HTTPURLResponse) {
            (try JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
        if url.path.hasSuffix("/auth/v1/token") {
            return try reply([
                "access_token": "a", "refresh_token": "r", "expires_in": 3600,
                "user": ["id": UUID().uuidString.lowercased(), "email": "me@example.com"]
            ])
        }

        guard request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true,
              request.value(forHTTPHeaderField: "apikey") != nil else { return try reply(["message": "no key"], 401) }

        if url.path.hasSuffix("/rpc/push_records") {
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let records = try (body["p_records"] as! [[String: Any]]).map { row -> SyncRecord in
                SyncRecord(
                    id: UUID(uuidString: row["id"] as! String)!,
                    kind: SyncKind(rawValue: row["kind"] as! String)!,
                    // jsonb rewrites key order and layout: do the same.
                    data: try JSONSerialization.data(withJSONObject: row["data"]!, options: [.sortedKeys]),
                    clientUpdatedAt: WireDate.parse(row["client_updated_at"] as! String)!,
                    deleted: row["deleted"] as? Bool ?? false,
                    deviceID: row["device_id"] as? String ?? ""
                )
            }
            let outcomes = try await backend.push(records)
            return try reply(outcomes.map { ["r_id": $0.id.uuidString.lowercased(), "r_applied": $0.applied, "r_server_updated_at": postgresStamp(Date())] })
        }

        if url.path.hasSuffix("/rest/v1/sync_records") {
            let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
            let since = items["server_updated_at"].flatMap { value -> Date? in
                value.hasPrefix("gt.") ? WireDate.parse(String(value.dropFirst(3))) : nil
            }
            let rows = try await backend.pull(since: since, limit: Int(items["limit"] ?? "500")!)
            return try reply(rows.map { record in
                [
                    "id": record.id.uuidString.lowercased(), "kind": record.kind.rawValue,
                    "data": try JSONSerialization.jsonObject(with: record.data),
                    "client_updated_at": postgresStamp(record.clientUpdatedAt),
                    "server_updated_at": postgresStamp(record.serverUpdatedAt!),
                    "deleted": record.deleted, "device_id": record.deviceID
                ] as [String: Any]
            })
        }
        return try reply(["message": "unknown route"], 404)
    }
}

@MainActor
final class SupabaseEndToEndTests: XCTestCase {
    private func makeDevices() async throws -> (SupabaseHTTPEmulator, Device, Device) {
        let http = SupabaseHTTPEmulator()
        let config = SupabaseConfig(url: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test")
        func device(_ name: String) async throws -> Device {
            let auth = SupabaseAuth(config: config, secrets: InMemorySecretStore(), http: http)
            _ = try await auth.signIn(email: "me@example.com", password: "pw")
            return Device(name, server: SupabaseTransport(config: config, auth: auth, http: http))
        }
        return (http, try await device("mac"), try await device("phone"))
    }

    func testGoalsHabitsAndTheirDetailsCrossTheWireIntact() async throws {
        let (_, mac, phone) = try await makeDevices()
        let task = mac.add("Prepare the talk", tags: ["lavoro", "brain"])
        mac.store.addSubtask(to: task.id, title: "Slides")
        mac.store.updateNote(id: task.id, note: "Ask the team about the “demo” – 100% ready? ✓")
        mac.store.setTheOne(id: task.id)
        XCTAssertTrue(mac.store.startTimer(id: task.id))
        mac.store.pauseTimer(id: task.id, at: Date().addingTimeInterval(95))
        _ = mac.store.addHabit(title: "Gym", schedule: HabitSchedule(kind: .custom, days: [2, 4, 6]), startDate: mac.day(0))

        await settle(mac, phone)

        assertSameState(mac, phone)
        let copy = try XCTUnwrap(phone.task(task.id))
        XCTAssertEqual(copy.tags, ["lavoro", "brain"])
        XCTAssertEqual(copy.subtasks.map(\.title), ["Slides"])
        XCTAssertEqual(copy.note, "Ask the team about the “demo” – 100% ready? ✓")
        XCTAssertTrue(copy.isTheOne)
        XCTAssertEqual(copy.focusSessions.count, 1)
        XCTAssertEqual(copy.focusSessions.first!.seconds, 95, accuracy: 1)
        XCTAssertEqual(phone.store.habits.first?.schedule.selectedDays, [2, 4, 6])
    }

    func testAnIdleRoundThroughHTTPSendsNothingAndChangesNothing() async throws {
        let (http, mac, phone) = try await makeDevices()
        mac.add("A"); mac.add("B")
        await settle(mac, phone)
        http.backend.resetCounters()
        await settle(mac, phone, rounds: 2)
        XCTAssertEqual(http.backend.pushedRecords, 0)
    }

    func testDeletionsAndEditsConvergeOverHTTP() async throws {
        let (_, mac, phone) = try await makeDevices()
        let a = mac.add("A"), b = mac.add("B")
        await settle(mac, phone)

        mac.store.deleteTask(id: a.id)
        phone.store.updateTaskStatus(id: b.id, newStatus: .done)
        await settle(mac, phone)

        XCTAssertNil(phone.task(a.id))
        XCTAssertEqual(mac.task(b.id)?.status, .done)
        assertSameState(mac, phone)
    }

    func testRandomEditsConvergeOverHTTPToo() async throws {
        for seed in 100..<112 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let (_, mac, phone) = try await makeDevices()
            let helper = SyncConvergenceTests()
            for _ in 0..<50 {
                let device = Bool.random(using: &rng) ? mac : phone
                helper.randomStepForReuse(on: device, using: &rng)
                if Int.random(in: 0..<100, using: &rng) < 35 { await (Bool.random(using: &rng) ? mac : phone).sync() }
            }
            await settle(mac, phone, rounds: 6)
            assertSameState(mac, phone)
        }
    }
}
