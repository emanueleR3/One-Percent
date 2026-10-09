import Foundation
import CryptoKit

/// Turns goals and habits into the JSON the server stores, and fingerprints them so a device can
/// tell what changed since it last synced.
public enum SyncCodec {
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Stable bytes for the same content: the fingerprint depends on it.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ task: TaskItem) throws -> Data {
        try makeEncoder().encode(task)
    }

    public static func encode(_ habit: Habit) throws -> Data {
        try makeEncoder().encode(habit)
    }

    public static func decodeTask(_ data: Data) throws -> TaskItem {
        try makeDecoder().decode(TaskItem.self, from: data)
    }

    public static func decodeHabit(_ data: Data) throws -> Habit {
        try makeDecoder().decode(Habit.self, from: data)
    }

    /// A short fingerprint of the encoded item (first 16 bytes of SHA-256, in hex).
    public static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
