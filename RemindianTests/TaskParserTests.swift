import XCTest
@testable import Remindian

final class TaskParserTests: XCTestCase {

    // MARK: - Basic Parsing

    func testSimpleTaskParsing() {
        let line = "- [ ] Buy groceries"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.title, "Buy groceries")
        XCTAssertFalse(task?.isCompleted ?? true)
    }

    func testCompletedTaskParsing() {
        let line = "- [x] Buy groceries ✅ 2026-01-15"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertTrue(task?.isCompleted ?? false)
        XCTAssertNotNil(task?.completedDate)
    }

    func testTaskWithDueDate() {
        let line = "- [ ] Submit report 📅 2026-03-15"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.title, "Submit report")
        XCTAssertNotNil(task?.dueDate)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(dateFormatter.string(from: task!.dueDate!), "2026-03-15")
    }

    func testTaskWithStartDate() {
        let line = "- [ ] Start project 🛫 2026-02-01 📅 2026-03-15"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertNotNil(task?.startDate)
        XCTAssertNotNil(task?.dueDate)
    }

    func testTaskWithScheduledDate() {
        let line = "- [ ] Review docs ⏳ 2026-02-20"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertNotNil(task?.scheduledDate)
    }

    // MARK: - Priority Parsing

    func testHighPriority() {
        let line = "- [ ] Urgent task ⏫"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.priority, .high)
    }

    func testMediumPriority() {
        let line = "- [ ] Normal task 🔼"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.priority, .medium)
    }

    func testLowPriority() {
        let line = "- [ ] Optional task 🔽"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.priority, .low)
    }

    func testPriorityWithFE0FVariationSelector() {
        // Some systems append U+FE0F (variation selector) to emoji
        let line = "- [ ] Urgent task ⏫\u{FE0F}"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.priority, .high)
    }

    // MARK: - Tag Parsing

    func testSingleTag() {
        let line = "- [ ] Work meeting #work"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertTrue(task?.tags.contains("#work") ?? false)
        XCTAssertEqual(task?.targetList, "work")
    }

    func testMultipleTags() {
        let line = "- [ ] Work meeting #work #urgent"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.tags.count, 2)
    }

    func testPlusPrefixTag() {
        // Issue #14: Support + prefix for list mappings
        let line = "- [ ] Work on feature +ProjectX"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertTrue(task?.tags.contains("+ProjectX") ?? false, "Should detect +ProjectX as a tag")
        XCTAssertEqual(task?.targetList, "ProjectX")
    }

    func testHashAndPlusTags() {
        let line = "- [ ] Review docs #work +ProjectX"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.tags.count, 2)
        XCTAssertTrue(task?.tags.contains("#work") ?? false)
        XCTAssertTrue(task?.tags.contains("+ProjectX") ?? false)
        // First tag (#work) determines the target list
        XCTAssertEqual(task?.targetList, "work")
    }

    // MARK: - Recurrence Stripping

    func testRecurrenceEmojiStripped() {
        let line = "- [ ] Pay rent 🔁 every month 📅 2026-03-01"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        // Title should NOT contain the recurrence text
        XCTAssertFalse(task!.title.contains("every month"))
        XCTAssertFalse(task!.title.contains("🔁"))
        XCTAssertEqual(task?.title.trimmingCharacters(in: .whitespaces), "Pay rent")
    }

    func testPlainTextRecurrenceStripped() {
        let line = "- [ ] Weekly standup every week 📅 2026-03-01"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        // Plain text recurrence should be stripped
        XCTAssertFalse(task!.title.contains("every week"))
    }

    // MARK: - Edge Cases

    func testNonTaskLine() {
        let line = "This is just a regular line"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNil(task)
    }

    func testBulletPointNotTask() {
        let line = "- Just a regular bullet"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNil(task)
    }

    func testWikilinkBulletNotTask() {
        // Issue #13: List items with wikilinks should NOT be parsed as tasks
        let line = "- [[Sarah]] coming to stay"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNil(task, "A list item starting with a wikilink should not be parsed as a task")
    }

    func testMultipleWikilinksBulletNotTask() {
        let line = "- [[Project X]] review with [[John]]"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNil(task, "A list item with wikilinks should not be parsed as a task")
    }

    func testEmptyCheckbox() {
        let line = "- [ ] "
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        // Should return nil or a task with empty title
        if let task = task {
            XCTAssertTrue(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testTaskWithWikiLinks() {
        let line = "- [ ] Talk to [[John Doe]] about [[Project X]]"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertTrue(task!.title.contains("[[John Doe]]"))
    }

    func testTaskWithAllMetadata() {
        let line = "- [ ] Complex task ⏫ 📅 2026-03-15 🛫 2026-03-01 ⏳ 2026-02-28 #work 🔁 every week"
        let task = SyncTask.fromObsidianLine(line, filePath: "/test.md", lineNumber: 1)
        XCTAssertNotNil(task)
        XCTAssertEqual(task?.priority, .high)
        XCTAssertNotNil(task?.dueDate)
        XCTAssertNotNil(task?.startDate)
        XCTAssertNotNil(task?.scheduledDate)
        XCTAssertTrue(task?.tags.contains("#work") ?? false)
        XCTAssertFalse(task!.title.contains("every week"))
    }
}
