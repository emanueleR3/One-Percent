import XCTest
@testable import OnePercent

final class QuickAddParserTests: XCTestCase {
    func testExtractsTrailingHashtagIntoTags() {
        let result = QuickAddParser.extractTags(from: "Call mom #family")
        XCTAssertEqual(result.title, "Call mom")
        XCTAssertEqual(result.tags, ["family"])
    }

    func testExtractsLeadingAndRepeatedTagsDeduplicatedAndLowercased() {
        let result = QuickAddParser.extractTags(from: "#Work Write report #work #deep-work")
        XCTAssertEqual(result.title, "Write report")
        XCTAssertEqual(result.tags, ["work", "deep-work"])
    }

    func testHashInsideAWordIsNotATag() {
        let result = QuickAddParser.extractTags(from: "Fix C# parser")
        XCTAssertEqual(result.title, "Fix C# parser")
        XCTAssertTrue(result.tags.isEmpty)
    }

    func testPurelyNumericHashIsAnIssueReferenceNotATag() {
        let result = QuickAddParser.extractTags(from: "Review PR #123 today")
        XCTAssertEqual(result.title, "Review PR #123 today")
        XCTAssertTrue(result.tags.isEmpty)
    }

    func testAccentedTagsAreKept() {
        let result = QuickAddParser.extractTags(from: "Chiamare la nonna #università")
        XCTAssertEqual(result.title, "Chiamare la nonna")
        XCTAssertEqual(result.tags, ["università"])
    }

    func testTitleWithoutTagsIsOnlyTrimmed() {
        let result = QuickAddParser.extractTags(from: "   Plain goal  ")
        XCTAssertEqual(result.title, "Plain goal")
        XCTAssertTrue(result.tags.isEmpty)
    }

    func testOnlyTagsLeavesAnEmptyTitle() {
        let result = QuickAddParser.extractTags(from: "#work")
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.tags, ["work"])
    }

    func testNormalizeTag() {
        XCTAssertEqual(TagNormalizer.normalize("#Lavoro "), "lavoro")
        XCTAssertEqual(TagNormalizer.normalize("deep work"), "deep-work")
        XCTAssertEqual(TagNormalizer.normalize("a!b?c"), "abc")
        XCTAssertNil(TagNormalizer.normalize("   "))
        XCTAssertNil(TagNormalizer.normalize("#"))
        XCTAssertEqual(TagNormalizer.normalize(String(repeating: "x", count: 40))?.count, TagNormalizer.maxLength)
    }
}
