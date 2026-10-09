import Foundation

/// Canonical form of a tag: lowercase, no `#`, spaces become hyphens, letters/digits/`_`/`-` only.
public enum TagNormalizer {
    public static let maxLength = 24

    public static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while text.hasPrefix("#") { text.removeFirst() }
        text = text.replacingOccurrences(of: " ", with: "-")
        let allowed = text.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
        var cleaned = String(String.UnicodeScalarView(allowed))
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        if cleaned.count > maxLength { cleaned = String(cleaned.prefix(maxLength)) }
        return cleaned.isEmpty ? nil : cleaned
    }
}

public struct QuickAddResult: Equatable, Sendable {
    public var title: String
    public var tags: [String]

    public init(title: String, tags: [String]) {
        self.title = title
        self.tags = tags
    }
}

/// Deterministic part of quick add: pulls `#tags` out of what was typed. Dates and repeats are
/// left to the on-device language model (see `SmartAddService`), never guessed with regexes.
public enum QuickAddParser {
    public static func extractTags(from raw: String) -> QuickAddResult {
        var tags: [String] = []
        var kept: [Substring] = []

        for word in raw.split(whereSeparator: { $0.isWhitespace }) {
            if word.hasPrefix("#"), let tag = hashtag(String(word)) {
                if !tags.contains(tag) { tags.append(tag) }
            } else {
                kept.append(word)
            }
        }
        return QuickAddResult(title: kept.joined(separator: " "), tags: tags)
    }

    /// `#work` -> `work`. Rejects `#123` (issue numbers) and anything that does not normalize.
    private static func hashtag(_ word: String) -> String? {
        let body = word.dropFirst()
        guard body.contains(where: { $0.isLetter }) else { return nil }
        // Trailing punctuation ("#work," / "#work.") is not part of the tag.
        let trimmed = body.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)"))
        return TagNormalizer.normalize(trimmed)
    }
}
