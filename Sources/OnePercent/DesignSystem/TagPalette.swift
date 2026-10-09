import SwiftUI

/// Muted, evenly weighted hues for tags. Mint, amber, lavender and orange are taken by status,
/// so these lean towards the rest of the wheel and stay readable on the near-black panel.
enum TagPalette {
    static let colors: [Color] = [
        Color(red: 255.0 / 255.0, green: 139.0 / 255.0, blue: 160.0 / 255.0), // rose
        Color(red: 255.0 / 255.0, green: 176.0 / 255.0, blue: 122.0 / 255.0), // peach
        Color(red: 232.0 / 255.0, green: 208.0 / 255.0, blue: 130.0 / 255.0), // sand
        Color(red: 176.0 / 255.0, green: 214.0 / 255.0, blue: 120.0 / 255.0), // lime
        Color(red: 110.0 / 255.0, green: 206.0 / 255.0, blue: 196.0 / 255.0), // teal
        Color(red: 122.0 / 255.0, green: 184.0 / 255.0, blue: 245.0 / 255.0), // sky
        Color(red: 178.0 / 255.0, green: 150.0 / 255.0, blue: 240.0 / 255.0), // violet
        Color(red: 226.0 / 255.0, green: 148.0 / 255.0, blue: 214.0 / 255.0)  // orchid
    ]

    static var count: Int { colors.count }

    static func color(at index: Int) -> Color {
        colors[((index % count) + count) % count]
    }

    /// Deterministic across launches (Swift's `hashValue` is randomized per process).
    static func defaultIndex(for tag: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in tag.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(count))
    }
}
