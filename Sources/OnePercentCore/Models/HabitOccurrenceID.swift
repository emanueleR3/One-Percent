import Foundation
import CryptoKit

/// A habit's goal for a given day always gets the same id, whichever device creates it.
///
/// With random ids, the Mac and the iPhone would each materialise "Gym, Monday" on their own and
/// sync would show two. With an id derived from the habit and the day, both create the *same*
/// goal and the two copies merge into one.
public enum HabitOccurrenceID {
    public static func make(habitID: UUID, day: Date, calendar: Calendar) -> UUID {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let key = "\(habitID.uuidString.lowercased())|\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5 layout
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
    }
}
