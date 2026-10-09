import XCTest
@testable import OnePercent
@testable import OnePercentCore
import OnePercentTestSupport

/// Keeps the shipped language packs honest: every string the code asks for exists in both tables,
/// placeholders line up, and the product names never get translated.
final class LocalizationCoverageTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func table(_ code: String) throws -> [String: String] {
        let url = repoRoot.appendingPathComponent("Resources/\(code).lproj/Localizable.strings")
        let dict = NSDictionary(contentsOf: url) as? [String: String]
        return try XCTUnwrap(dict, "\(code).lproj/Localizable.strings is missing or malformed")
    }

    /// Every `L("…")` and `Lp("…", "…", …)` literal in the sources.
    private func usedKeys() throws -> Set<String> {
        let folders = ["Sources/OnePercent", "Sources/OnePercentCore", "iOS/OnePercentiOS"].map { repoRoot.appendingPathComponent($0) }
        let files = folders.compactMap { FileManager.default.enumerator(at: $0, includingPropertiesForKeys: nil) }
        let literal = "\"((?:[^\"\\\\]|\\\\.)*)\""
        let single = try NSRegularExpression(pattern: "\\bL\\(\(literal)")
        let plural = try NSRegularExpression(pattern: "\\bLp\\(\(literal),\\s*\(literal)")
        var keys = Set<String>()
        for case let url as URL in files.joined() where url.pathExtension == "swift" && url.lastPathComponent != "Localizer.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for regex in [single, plural] {
                for match in regex.matches(in: text, range: range) {
                    for group in 1..<match.numberOfRanges {
                        guard let r = Range(match.range(at: group), in: text) else { continue }
                        keys.insert(Self.unescape(String(text[r])))
                    }
                }
            }
        }
        return keys
    }

    private static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func placeholders(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dfs]")
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
            String(text[Range($0.range, in: text)!])
        }.sorted()
    }

    func testBothPacksExist() throws {
        XCTAssertFalse(try table("en").isEmpty)
        XCTAssertFalse(try table("it").isEmpty)
    }

    func testEveryUsedKeyIsInBothPacks() throws {
        let keys = try usedKeys()
        XCTAssertGreaterThan(keys.count, 200, "key scan found suspiciously few strings")
        let en = try table("en"), it = try table("it")
        XCTAssertEqual(keys.subtracting(en.keys).sorted(), [], "missing from en")
        XCTAssertEqual(keys.subtracting(it.keys).sorted(), [], "missing from it")
    }

    func testNoStaleKeys() throws {
        let keys = try usedKeys()
        XCTAssertEqual(Set(try table("it").keys).subtracting(keys).sorted(), [], "unused Italian entries")
        XCTAssertEqual(Set(try table("en").keys).subtracting(keys).sorted(), [], "unused English entries")
    }

    func testEnglishIsIdentity() throws {
        for (key, value) in try table("en") {
            XCTAssertEqual(key, value)
        }
    }

    func testPlaceholdersMatchBetweenLanguages() throws {
        let it = try table("it")
        for (key, value) in it {
            XCTAssertEqual(placeholders(key), placeholders(value), "placeholder mismatch for “\(key)”")
        }
    }

    func testItalianValuesAreNeverEmpty() throws {
        for (key, value) in try table("it") {
            XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "empty Italian text for “\(key)”")
        }
    }

    func testProtectedTermsStayIdentical() throws {
        let it = try table("it")
        for term in ["The One", "One Percent", "Apple Intelligence"] {
            for (key, value) in it where key.contains(term) {
                XCTAssertTrue(value.contains(term), "“\(term)” must survive translation in “\(key)”")
            }
        }
    }

    func testBundledPacksLoadThroughTheLocalizer() throws {
        let localizer = Localizer(roots: [repoRoot.appendingPathComponent("Resources")])
        localizer.setLanguage(.italian)
        XCTAssertEqual(localizer.string("Settings"), "Impostazioni")
        XCTAssertEqual(localizer.string("The One"), "The One")
        localizer.setLanguage(.english)
        XCTAssertEqual(localizer.string("Settings"), "Settings")
    }
}
