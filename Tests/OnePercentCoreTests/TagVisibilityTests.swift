import XCTest
@testable import OnePercentCore
import OnePercentTestSupport

/// A tag the user has used stays visible and selectable, whether its goals are open or finished.
@MainActor
final class TagVisibilityTests: XCTestCase {
    private var store: TaskStore!

    override func setUp() async throws {
        store = TaskStore(persistence: MockTaskPersistence(), dateService: DateService(), habitPersistence: InMemoryHabitPersistence())
    }

    @discardableResult
    private func add(_ title: String, tags: [String], status: TaskStatus = .todo) -> TaskItem {
        let task = store.addTask(title: title, tags: tags)!
        if status != .todo { store.updateTaskStatus(id: task.id, newStatus: status) }
        return task
    }

    func testATagUsedOnlyOnADoneGoalIsStillKnown() {
        add("Dentista", tags: ["personale"], status: .done)
        XCTAssertTrue(store.allTagNames.contains("personale"))
        XCTAssertEqual(store.tagUsage.first { $0.tag == "personale" }?.count, 1)
    }

    func testEveryKnownTagIsSuggestedNotJustTheMostUsedThree() {
        for index in 0..<3 { add("Lavoro \(index)", tags: ["lavoro"]) }
        for index in 0..<2 { add("Brain \(index)", tags: ["brain"]) }
        add("Studio", tags: ["galeni"])
        add("Dentista", tags: ["personale"], status: .done)
        let blank = add("Nuovo", tags: [])

        let suggestions = store.tagSuggestions(excluding: blank.tags)

        XCTAssertEqual(suggestions, ["lavoro", "brain", "galeni", "personale"])
        XCTAssertTrue(suggestions.contains("personale"), "a tag from a finished goal must not drop out of reach")
    }

    func testSuggestionsSkipTagsTheGoalAlreadyHas() {
        add("Dentista", tags: ["personale"], status: .done)
        add("Lavoro", tags: ["lavoro"])
        XCTAssertEqual(store.tagSuggestions(excluding: ["lavoro"]), ["personale"])
    }

    func testAddingAKnownSuggestionStillWorksForAFinishedGoalTag() {
        add("Dentista", tags: ["personale"], status: .done)
        let goal = add("Chiamare", tags: [])
        store.addTag("personale", to: goal.id)
        XCTAssertEqual(store.allTasks.first { $0.id == goal.id }?.tags, ["personale"])
        XCTAssertEqual(store.tagUsage.first { $0.tag == "personale" }?.count, 2)
    }
}
