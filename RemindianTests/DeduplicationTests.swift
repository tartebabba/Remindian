import XCTest
@testable import Remindian

final class DeduplicationTests: XCTestCase {

    // MARK: - Task ID Generation

    func testStableIdGeneration() {
        let task1 = SyncTask(
            title: "Test task",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/test.md",
                lineNumber: 5,
                originalLine: "- [ ] Test task"
            )
        )
        let task2 = SyncTask(
            title: "Test task",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/test.md",
                lineNumber: 5,
                originalLine: "- [ ] Test task"
            )
        )

        let id1 = SyncState.generateObsidianId(task: task1)
        let id2 = SyncState.generateObsidianId(task: task2)
        XCTAssertEqual(id1, id2, "Same task content should produce same ID")
    }

    func testDifferentTasksGetDifferentIds() {
        let task1 = SyncTask(
            title: "Task A",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/test.md",
                lineNumber: 1,
                originalLine: "- [ ] Task A"
            )
        )
        let task2 = SyncTask(
            title: "Task B",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/test.md",
                lineNumber: 2,
                originalLine: "- [ ] Task B"
            )
        )

        let id1 = SyncState.generateObsidianId(task: task1)
        let id2 = SyncState.generateObsidianId(task: task2)
        XCTAssertNotEqual(id1, id2, "Different tasks should have different IDs")
    }

    func testIdStableAcrossLineReordering() {
        // Content-based IDs should be stable even if line numbers change
        // (for NON-recurring tasks; recurring tasks deliberately include line number — see #57).
        let task1 = SyncTask(
            title: "Test task",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/test.md",
                lineNumber: 5,
                originalLine: "- [ ] Test task"
            )
        )
        let task2 = SyncTask(
            title: "Test task",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/test.md",
                lineNumber: 10,  // Different line number
                originalLine: "- [ ] Test task"
            )
        )

        let id1 = SyncState.generateObsidianId(task: task1)
        let id2 = SyncState.generateObsidianId(task: task2)
        XCTAssertEqual(id1, id2, "Content-hash IDs should be stable across line reordering for non-recurring tasks")
    }

    // MARK: - Recurring-task ID disambiguation (#57 Phase A)

    /// The Obsidian Tasks plugin creates a new task line for each occurrence of a
    /// recurring task (on completion it inserts the next uncompleted copy above
    /// the now-completed line). If both copies shared the same obsidianId, one
    /// would silently overwrite the other in the in-memory map, causing missed
    /// occurrences and duplicates during sync (#57). Including lineNumber for
    /// recurring tasks gives each copy a distinct ID.
    func testRecurringTaskIdsIncludeLineNumber() {
        let completedCopy = SyncTask(
            title: "Pay rent",
            isCompleted: true,
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/test.md",
                lineNumber: 10,
                originalLine: "- [x] Pay rent 🔁 every month 📅 2026-01-01 ✅ 2026-01-15"
            ),
            recurrenceRule: "🔁 every month"
        )
        let newUncompletedCopy = SyncTask(
            title: "Pay rent",
            isCompleted: false,
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/test.md",
                lineNumber: 9,  // Inserted just above the completed one
                originalLine: "- [ ] Pay rent 🔁 every month 📅 2026-02-01"
            ),
            recurrenceRule: "🔁 every month"
        )

        let completedId = SyncState.generateObsidianId(task: completedCopy)
        let newId = SyncState.generateObsidianId(task: newUncompletedCopy)

        XCTAssertNotEqual(
            completedId, newId,
            "Recurring task occurrences at different lines must get distinct IDs — otherwise they collide in the sync map (#57)"
        )
    }

    /// Non-recurring tasks with the same content must still collapse to the same ID
    /// even at different lines — otherwise normal reordering would break sync mappings.
    func testNonRecurringTaskIdsDoNotIncludeLineNumber() {
        let task1 = SyncTask(
            title: "Buy milk",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/test.md",
                lineNumber: 5,
                originalLine: "- [ ] Buy milk"
            )
            // recurrenceRule is nil
        )
        let task2 = SyncTask(
            title: "Buy milk",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/test.md",
                lineNumber: 42,
                originalLine: "- [ ] Buy milk"
            )
        )
        XCTAssertEqual(
            SyncState.generateObsidianId(task: task1),
            SyncState.generateObsidianId(task: task2),
            "Non-recurring tasks must keep stable IDs across reordering"
        )
    }

    // MARK: - Task Hash

    func testSameTaskSameHash() {
        let task = SyncTask(
            title: "Test",
            isCompleted: false,
            priority: .high,
            dueDate: Date(timeIntervalSince1970: 1000000)
        )
        let hash1 = SyncState.generateTaskHash(task)
        let hash2 = SyncState.generateTaskHash(task)
        XCTAssertEqual(hash1, hash2)
    }

    func testDifferentCompletionDifferentHash() {
        let task1 = SyncTask(title: "Test", isCompleted: false)
        let task2 = SyncTask(title: "Test", isCompleted: true)
        let hash1 = SyncState.generateTaskHash(task1)
        let hash2 = SyncState.generateTaskHash(task2)
        XCTAssertNotEqual(hash1, hash2)
    }

    // MARK: - Sync State Mapping

    func testAddAndRetrieveMapping() {
        var state = SyncState()
        state.addOrUpdateMapping(
            obsidianId: "obs1",
            remindersId: "rem1",
            obsidianHash: "hash1",
            remindersHash: "hash1"
        )

        XCTAssertEqual(state.mappings.count, 1)
        XCTAssertEqual(state.mappings.first?.obsidianId, "obs1")
        XCTAssertEqual(state.mappings.first?.remindersId, "rem1")
    }

    func testUpdateExistingMapping() {
        var state = SyncState()
        state.addOrUpdateMapping(
            obsidianId: "obs1",
            remindersId: "rem1",
            obsidianHash: "hash1",
            remindersHash: "hash1"
        )
        state.addOrUpdateMapping(
            obsidianId: "obs1",
            remindersId: "rem1",
            obsidianHash: "hash2",
            remindersHash: "hash2"
        )

        XCTAssertEqual(state.mappings.count, 1, "Should update existing mapping, not create duplicate")
    }

    // MARK: - Cross-file dedup (#46)

    func testSameTitleDifferentFilesGetDifferentIds() {
        // Same task title in different files should produce different IDs (#46)
        let task1 = SyncTask(
            title: "Review imported meeting notes",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/vault/2026-03-20 - Meeting 1.md",
                lineNumber: 3,
                originalLine: "- [ ] Review imported meeting notes"
            )
        )
        let task2 = SyncTask(
            title: "Review imported meeting notes",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/vault/2026-03-19 - Meeting ABC.md",
                lineNumber: 3,
                originalLine: "- [ ] Review imported meeting notes"
            )
        )

        let id1 = SyncState.generateObsidianId(task: task1)
        let id2 = SyncState.generateObsidianId(task: task2)
        XCTAssertNotEqual(id1, id2, "Same title in different files must get different IDs")
    }

    func testRemoveMapping() {
        var state = SyncState()
        state.addOrUpdateMapping(
            obsidianId: "obs1",
            remindersId: "rem1",
            obsidianHash: "hash1",
            remindersHash: "hash1"
        )
        state.removeMapping(obsidianId: "obs1")

        XCTAssertEqual(state.mappings.count, 0)
    }
}
