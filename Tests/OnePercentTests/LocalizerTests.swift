import XCTest
@testable import OnePercent

final class LocalizerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("op-l10n-\(UUID().uuidString)", isDirectory: true)
        try write("en", ["Hello": "Hello", "Goals %d": "Goals %d", "%d goal left": "%d goal left", "%d goals left": "%d goals left"])
        try write("it", ["Hello": "Ciao", "Goals %d": "Obiettivi %d", "%d goal left": "%d obiettivo rimasto", "%d goals left": "%d obiettivi rimasti", "Only Italian": "Solo italiano"])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ code: String, _ table: [String: String]) throws {
        let folder = dir.appendingPathComponent("\(code).lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let body = table.map { "\"\($0.key)\" = \"\($0.value)\";" }.joined(separator: "\n")
        try body.write(to: folder.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
    }

    // MARK: - Lookup

    func testEnglishIsTheDefault() {
        let localizer = Localizer(roots: [dir])
        XCTAssertEqual(localizer.language, .english)
        XCTAssertEqual(localizer.string("Hello"), "Hello")
    }

    func testItalianLookup() {
        let localizer = Localizer(roots: [dir])
        localizer.setLanguage(.italian)
        XCTAssertEqual(localizer.string("Hello"), "Ciao")
    }

    func testAMissingKeyFallsBackToTheKeyItself() {
        let localizer = Localizer(roots: [dir])
        localizer.setLanguage(.italian)
        XCTAssertEqual(localizer.string("Never translated"), "Never translated")
    }

    func testAKeyOnlyInItalianIsNotUsedForEnglish() {
        let localizer = Localizer(roots: [dir])
        XCTAssertEqual(localizer.string("Only Italian"), "Only Italian")
    }

    func testAKeyMissingFromItalianFallsBackToEnglishText() throws {
        try write("en", ["Hello": "Hello", "Extra": "Extra (en)"])
        let localizer = Localizer(roots: [dir])
        localizer.setLanguage(.italian)
        XCTAssertEqual(localizer.string("Extra"), "Extra (en)")
    }

    func testWithoutAnyFilesEverythingIsTheKey() {
        let localizer = Localizer(roots: [dir.appendingPathComponent("nowhere")])
        localizer.setLanguage(.italian)
        XCTAssertEqual(localizer.string("Hello"), "Hello")
    }

    func testSwitchingLanguageAtRuntime() {
        let localizer = Localizer(roots: [dir])
        localizer.setLanguage(.italian)
        XCTAssertEqual(localizer.string("Hello"), "Ciao")
        localizer.setLanguage(.english)
        XCTAssertEqual(localizer.string("Hello"), "Hello")
    }

    // MARK: - Formatting

    func testFormattedStrings() {
        let localizer = Localizer(roots: [dir])
        localizer.setLanguage(.italian)
        XCTAssertEqual(localizer.format("Goals %d", 3), "Obiettivi 3")
    }

    func testPluralsPickTheRightKey() {
        let localizer = Localizer(roots: [dir])
        XCTAssertEqual(localizer.plural("%d goal left", "%d goals left", 1), "1 goal left")
        XCTAssertEqual(localizer.plural("%d goal left", "%d goals left", 3), "3 goals left")
        localizer.setLanguage(.italian)
        XCTAssertEqual(localizer.plural("%d goal left", "%d goals left", 1), "1 obiettivo rimasto")
        XCTAssertEqual(localizer.plural("%d goal left", "%d goals left", 0), "0 obiettivi rimasti")
    }

    // MARK: - Choosing a language

    func testExplicitChoicesWin() {
        XCTAssertEqual(LanguageChoice.english.resolve(preferred: ["it-IT"]), .english)
        XCTAssertEqual(LanguageChoice.italian.resolve(preferred: ["en-US"]), .italian)
    }

    func testSystemFollowsTheFirstSupportedPreferredLanguage() {
        XCTAssertEqual(LanguageChoice.system.resolve(preferred: ["it-IT", "en-US"]), .italian)
        XCTAssertEqual(LanguageChoice.system.resolve(preferred: ["en-GB"]), .english)
        XCTAssertEqual(LanguageChoice.system.resolve(preferred: ["fr-FR", "it-IT"]), .italian, "skips languages we do not ship")
        XCTAssertEqual(LanguageChoice.system.resolve(preferred: ["fr-FR", "de-DE"]), .english, "unknown means English")
        XCTAssertEqual(LanguageChoice.system.resolve(preferred: []), .english)
    }

    func testNativeNames() {
        XCTAssertEqual(AppLanguage.english.nativeName, "English")
        XCTAssertEqual(AppLanguage.italian.nativeName, "Italiano")
    }

    // MARK: - Strings file parsing

    func testEscapesInStringsFilesAreUnderstood() throws {
        let folder = dir.appendingPathComponent("en.lproj", isDirectory: true)
        try "\"Say \\\"hi\\\"\" = \"Line one\\nLine two\";".write(to: folder.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        let localizer = Localizer(roots: [dir])
        XCTAssertEqual(localizer.string("Say \"hi\""), "Line one\nLine two")
    }
}
