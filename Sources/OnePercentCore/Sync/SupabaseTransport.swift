import Foundation

/// Talks to the `sync_records` table through Supabase's REST API (see `supabase/README.md`).
public final class SupabaseTransport: SyncTransport, @unchecked Sendable {
    private let config: SupabaseConfig
    private let auth: SupabaseAuth
    private let http: HTTPSending

    public init(config: SupabaseConfig = .onePercent, auth: SupabaseAuth, http: HTTPSending = URLSession.shared) {
        self.config = config
        self.auth = auth
        self.http = http
    }

    // MARK: Push

    public func push(_ records: [SyncRecord]) async throws -> [PushOutcome] {
        guard !records.isEmpty else { return [] }
        var payload: [[String: Any]] = []
        for record in records {
            guard let object = try? JSONSerialization.jsonObject(with: record.data) else { throw SyncError.invalidResponse }
            payload.append([
                "id": record.id.uuidString.lowercased(),
                "kind": record.kind.rawValue,
                "data": object,
                "client_updated_at": WireDate.string(record.clientUpdatedAt),
                "deleted": record.deleted,
                "device_id": record.deviceID
            ])
        }
        let body = try JSONSerialization.data(withJSONObject: ["p_records": payload])
        let data = try await perform(method: "POST", path: "rest/v1/rpc/push_records", body: body)

        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { throw SyncError.invalidResponse }
        return try rows.map { row in
            guard let id = (row["r_id"] as? String).flatMap(UUID.init(uuidString:)), let applied = row["r_applied"] as? Bool else {
                throw SyncError.invalidResponse
            }
            return PushOutcome(id: id, applied: applied)
        }
    }

    // MARK: Pull

    public func pull(since: Date?, limit: Int) async throws -> [SyncRecord] {
        var query = [
            URLQueryItem(name: "select", value: "id,kind,data,client_updated_at,server_updated_at,deleted,device_id"),
            URLQueryItem(name: "order", value: "server_updated_at.asc,id.asc"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let since {
            query.append(URLQueryItem(name: "server_updated_at", value: "gt." + WireDate.string(since)))
        }
        let data = try await perform(method: "GET", path: "rest/v1/sync_records", query: query)
        guard let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { throw SyncError.invalidResponse }

        var records: [SyncRecord] = []
        for row in rows {
            guard let id = (row["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let kind = (row["kind"] as? String).flatMap(SyncKind.init(rawValue:)),
                  let clientText = row["client_updated_at"] as? String, let client = WireDate.parse(clientText),
                  let serverText = row["server_updated_at"] as? String, let server = WireDate.parse(serverText),
                  let object = row["data"], let payload = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
            else { continue }   // a kind from a newer app, or a row this version cannot make sense of
            records.append(SyncRecord(
                id: id, kind: kind, data: payload, clientUpdatedAt: client,
                deleted: row["deleted"] as? Bool ?? false, deviceID: row["device_id"] as? String ?? "",
                serverUpdatedAt: server
            ))
        }
        return records
    }

    // MARK: HTTP

    private func perform(method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        for attempt in 0..<2 {
            let session = try await auth.validSession()
            var request = URLRequest(url: config.endpoint(path, query: query))
            request.httpMethod = method
            request.timeoutInterval = 30
            request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }

            let data: Data, response: HTTPURLResponse
            do {
                (data, response) = try await http.send(request)
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                throw SyncError.offline
            }

            switch response.statusCode {
            case 200..<300:
                return data
            case 401 where attempt == 0:
                // The token was rejected (revoked, clock skew): refresh once and try again.
                _ = try? await auth.refreshNow()
                continue
            case 401, 403:
                throw SyncError.notSignedIn
            default:
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw SyncError.server(status: response.statusCode, message: json?["message"] as? String ?? "HTTP \(response.statusCode)")
            }
        }
        throw SyncError.notSignedIn
    }
}
