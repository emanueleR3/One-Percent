import XCTest
@testable import OnePercent

@MainActor
final class TagVocabularyTests: XCTestCase {
    private var store: TaskStore!

    override func setUp() async throws {
        store = TaskStore(
            persistence: MockTaskPersistence(),
            dateService: DateService(calendar: Calendar(identifier: .gregorian)),
            habitPersistence: InMemoryHabitPersistence()
        )
    }

    func testVocabularyListsTagsByUsageWithRecentExamples() {
        for title in ["Write spec", "Review PR", "Plan sprint", "Fix bug"] {
            store.addTask(title: title, tags: ["work"])
        }
        store.addTask(title: "Call mom", tags: ["family"])

        let vocabulary = store.tagVocabulary(maxTags: 5, examplesPerTag: 3)

        XCTAssertEqual(vocabulary.map(\.tag), ["work", "family"])
        XCTAssertEqual(vocabulary[0].examples.count, 3)
        XCTAssertEqual(vocabulary[1].examples, ["Call mom"])
    }

    func testExamplesAreDistinctAndMostRecentFirst() {
        store.addTask(title: "Same", tags: ["work"])
        store.addTask(title: "Same", tags: ["work"])
        store.addTask(title: "Newest", tags: ["work"])
        let examples = store.tagVocabulary()[0].examples
        XCTAssertEqual(examples, ["Newest", "Same"])
    }

    func testVocabularyIsCappedAndSkipsUnusedTags() {
        for index in 0..<12 {
            store.addTask(title: "g\(index)", tags: ["t\(index)"])
        }
        XCTAssertEqual(store.tagVocabulary(maxTags: 8).count, 8)

        let empty = TaskStore(persistence: MockTaskPersistence(), dateService: DateService(), habitPersistence: InMemoryHabitPersistence())
        XCTAssertTrue(empty.tagVocabulary().isEmpty)
    }
}
