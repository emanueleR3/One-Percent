import SwiftUI

/// The same near-black look as the Mac panel, so the two apps read as one product.
enum Theme {
    static let background = Color(red: 5 / 255, green: 5 / 255, blue: 5 / 255)
    static let surface = Color.white.opacity(0.055)
    static let surfaceStrong = Color.white.opacity(0.10)
    static let hairline = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.09)

    static let primaryText = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let secondaryText = Color(red: 161 / 255, green: 161 / 255, blue: 166 / 255)
    static let tertiaryText = Color(red: 119 / 255, green: 119 / 255, blue: 124 / 255)

    static let mint = Color(red: 143 / 255, green: 215 / 255, blue: 164 / 255)
    static let amber = Color(red: 231 / 255, green: 198 / 255, blue: 110 / 255)
    static let lavender = Color(red: 150 / 255, green: 165 / 255, blue: 255 / 255)
    static let orange = Color(red: 255 / 255, green: 150 / 255, blue: 88 / 255)
    static let slate = Color(red: 183 / 255, green: 183 / 255, blue: 201 / 255)
    static let destructive = Color(red: 255 / 255, green: 105 / 255, blue: 97 / 255)

    static func color(for status: TaskStatusColorKey) -> Color {
        switch status {
        case .todo: return secondaryText
        case .inProgress: return amber
        case .done: return mint
        case .deferred: return slate
        }
    }
}

enum TaskStatusColorKey { case todo, inProgress, done, deferred }

/// Muted hues for tags (matches the Mac palette).
enum TagColors {
    static let colors: [Color] = [
        Color(red: 255 / 255, green: 139 / 255, blue: 160 / 255),
        Color(red: 255 / 255, green: 176 / 255, blue: 122 / 255),
        Color(red: 232 / 255, green: 208 / 255, blue: 130 / 255),
        Color(red: 176 / 255, green: 214 / 255, blue: 120 / 255),
        Color(red: 110 / 255, green: 206 / 255, blue: 196 / 255),
        Color(red: 122 / 255, green: 184 / 255, blue: 245 / 255),
        Color(red: 178 / 255, green: 150 / 255, blue: 240 / 255),
        Color(red: 226 / 255, green: 148 / 255, blue: 214 / 255)
    ]

    static func color(at index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }

    /// Deterministic across launches, and the same as on the Mac.
    static func defaultIndex(for tag: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in tag.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(colors.count))
    }
}
