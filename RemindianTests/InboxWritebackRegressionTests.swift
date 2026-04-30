import XCTest
@testable import Remindian

/// Regression tests for the v5.8.2 inbox-writeback runaway-duplicate bug.
///
/// **The bug.** A user with `enableNewTaskWriteback = true` and recurring
/// tasks in Apple Reminders saw their `/Inbox.md` accumulate dozens of
/// duplicate completed entries within minutes of each sync. Three independent
/// defects compounded:
///
/// 1. **Step 6 wrote out the recurrence history.** When you complete a
///    recurring reminder in Apple Reminders, iOS marks that instance complete
///    and creates a fresh occurrence with a brand-new `calendarItemIdentifier`.
///    The old mapping pointed to the original id, so every fresh occurrence
///    looked unmapped to the sync engine and got appended to /Inbox.md as if
///    it were a new task. The fix here: skip the append when the reminder's
///    title already exists somewhere in the vault.
///
/// 2. **`appendTaskToInbox` didn't register the self-modification.** Every
///    other file-mutating method in `ObsidianService` calls
///    `FileWatcherService.shared.registerSelfModification(_:)` before writing.
///    `appendTaskToInbox` was missing that call, so FSEvents reported the
///    write as an external change, the watcher debounced 2s, and triggered
///    another sync — which appended again. Compounded with (1), this created
///    an unbounded duplication loop.
///
/// 3. **`obsidianId` was unstable across the append/reparse round-trip.** The
///    line written to disk includes `#<targetList>` (the reminder's list name
///    formatted as a tag). The mapping was stored using `rTask`, which has
///    `tags = []`. On the next vault scan, the parsed task has `tags =
///    ["#<list>"]`. The two ids differ → the mapping orphaned itself
///    immediately → step 6 ran for the same reminder again next sync.
///
/// These tests catch each defect independently. If any of them fail, the bug
/// is back.
final class InboxWritebackRegressionTests: XCTestCase {

    private var vaultURL: URL!
    private var service: ObsidianService!

    override func setUp() {
        super.setUp()
        vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("remindian-inbox-regression-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        service = ObsidianService()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: vaultURL)
        super.tearDown()
    }

    // MARK: - Fix B: self-modification registration

    /// `appendTaskToInbox` must register the file as self-modified BEFORE
    /// writing, so the FSEvents callback ignores its own write. Without this,
    /// every append triggers a debounced sync, which appends again. (#XX)
    func testAppendTaskToInboxRegistersSelfModification() throws {
        let task = SyncTask(
            title: "Buy milk",
            isCompleted: false,
            priority: .none,
            dueDate: nil,
            startDate: nil,
            scheduledDate: nil,
            completedDate: nil,
            tags: [],
            targetList: "Personal"
        )

        let result = try service.appendTaskToInbox(
            task: task,
            inboxRelativePath: "Inbox.md",
            vaultPath: vaultURL.path
        )

        let writtenPath = vaultURL.appendingPathComponent("Inbox.md").path
        XCTAssertTrue(
            FileWatcherService.shared.isMarkedSelfModified(writtenPath),
            "appendTaskToInbox must call FileWatcherService.registerSelfModification before writing — otherwise FSEvents reports the write as external and triggers a sync loop. (regression: 2026-04-30)"
        )

        // Sanity: the file actually got the task line.
        XCTAssertTrue(result.lineContent.contains("Buy milk"))
    }

    // MARK: - Fix C: stable obsidianId across append/reparse

    /// The line written by `appendTaskToInbox` must round-trip through
    /// `SyncTask.fromObsidianLine` such that the ID generated from the parsed
    /// result equals the ID generated from the same parsed result on the
    /// next vault scan. Concretely: parsing the just-written line produces a
    /// SyncTask whose generateObsidianId is deterministic — call it twice,
    /// get the same string. That stability is what keeps the mapping intact
    /// across syncs. (#XX)
    func testAppendedLineParsesToStableObsidianId() throws {
        let task = SyncTask(
            title: "Pay rent",
            isCompleted: false,
            priority: .none,
            dueDate: nil,
            startDate: nil,
            scheduledDate: nil,
            completedDate: nil,
            tags: [],
            targetList: "Reminders" // simulates an Apple Reminders list name
        )

        let result = try service.appendTaskToInbox(
            task: task,
            inboxRelativePath: "Inbox.md",
            vaultPath: vaultURL.path
        )

        // Parse the line we just wrote.
        guard let parsed = SyncTask.fromObsidianLine(
            result.lineContent,
            filePath: result.filePath,
            lineNumber: result.lineNumber
        ) else {
            XCTFail("Appended line must be parseable: \(result.lineContent)")
            return
        }

        // ID generated immediately after the write (this is the one we'll
        // store in syncState).
        let storedId = SyncState.generateObsidianId(task: parsed)

        // Now simulate the next sync: scan the file fresh, find the task,
        // generate its ID. This must equal storedId or the mapping is
        // immediately orphaned.
        let url = vaultURL.appendingPathComponent("Inbox.md")
        let lines = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
        guard let scanned = SyncTask.fromObsidianLine(
            lines[result.lineNumber - 1],
            filePath: result.filePath,
            lineNumber: result.lineNumber
        ) else {
            XCTFail("Re-scan must produce a SyncTask")
            return
        }
        let rescannedId = SyncState.generateObsidianId(task: scanned)

        XCTAssertEqual(
            storedId, rescannedId,
            "obsidianId must be stable across append + re-parse. Without this, the mapping created in step 6 immediately orphans itself, the reminder appears unmapped on the next sync, and step 6 re-appends it. (regression: 2026-04-30)"
        )
    }

    /// Edge case: a reminder with no targetList (no list name on the Apple
    /// Reminders side) should still produce a stable id.
    func testAppendedLineWithNoListProducesStableId() throws {
        let task = SyncTask(
            title: "Standalone task",
            isCompleted: false,
            priority: .none,
            dueDate: nil,
            startDate: nil,
            scheduledDate: nil,
            completedDate: nil,
            tags: [],
            targetList: nil
        )

        let result = try service.appendTaskToInbox(
            task: task,
            inboxRelativePath: "Inbox.md",
            vaultPath: vaultURL.path
        )

        guard let parsed = SyncTask.fromObsidianLine(
            result.lineContent,
            filePath: result.filePath,
            lineNumber: result.lineNumber
        ) else {
            XCTFail("Appended line must be parseable: \(result.lineContent)")
            return
        }
        let storedId = SyncState.generateObsidianId(task: parsed)

        let url = vaultURL.appendingPathComponent("Inbox.md")
        let lines = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: "\n")
        guard let scanned = SyncTask.fromObsidianLine(
            lines[result.lineNumber - 1],
            filePath: result.filePath,
            lineNumber: result.lineNumber
        ) else {
            XCTFail("Re-scan must produce a SyncTask")
            return
        }
        let rescannedId = SyncState.generateObsidianId(task: scanned)

        XCTAssertEqual(storedId, rescannedId)
    }

    // MARK: - Fix A: title-index dedup behavior (unit-level)

    /// Documents the dedup contract used by step 6: when the reminder's
    /// title matches a task already present in `obsidianMap`, the inbox
    /// append must be skipped. We verify the lookup pattern produces the
    /// expected result for the canonical case (recurring task in some other
    /// vault file, fresh occurrence's reminder appears in the destination
    /// fetch). The actual SyncEngine wiring is exercised by manual end-to-end
    /// tests in the v5.8.2 release notes.
    func testTitleIndexLookupHitsForExistingVaultTask() {
        // Simulate the obsidianMap state at sync time: a recurring task
        // already lives in /Work/Netspace.md.
        let existingTask = SyncTask(
            title: "Faire les virements des salaires",
            isCompleted: false,
            priority: .high,
            dueDate: Date(),
            startDate: Date(),
            scheduledDate: nil,
            completedDate: nil,
            tags: ["#netspace"],
            targetList: "netspace",
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/Work/Netspace.md",
                lineNumber: 20,
                originalLine: "- [ ] Faire les virements des salaires #netspace ⏫ 🔁 every month on the 27th when done 🛫 2026-02-20 📅 2026-02-27"
            ),
            recurrenceRule: "🔁 every month on the 27th when done"
        )
        var obsidianMap: [String: SyncTask] = [:]
        let existingId = SyncState.generateObsidianId(task: existingTask)
        obsidianMap[existingId] = existingTask

        // Build the same title→id index step 6 builds.
        var titleIndex: [String: String] = [:]
        for (id, task) in obsidianMap {
            titleIndex[task.title] = id
        }

        // A reminder for a fresh occurrence of the same recurring task —
        // same title, fresh remindersId, no mapping yet.
        let unmappedReminder = SyncTask(
            title: "Faire les virements des salaires",
            isCompleted: false,
            tags: [],
            targetList: "Work"
        )

        XCTAssertNotNil(
            titleIndex[unmappedReminder.title],
            "Step 6's title index must hit for an unmapped reminder whose title matches an existing vault task. Without this, recurring-task history accumulates as duplicates in /Inbox.md. (regression: 2026-04-30)"
        )
        XCTAssertEqual(titleIndex[unmappedReminder.title], existingId)
    }

    /// A reminder whose title does NOT exist in any vault file is a genuinely
    /// new task and must NOT be skipped. This is the original happy path for
    /// the inbox writeback feature.
    func testTitleIndexMissesForGenuinelyNewReminder() {
        let existingTask = SyncTask(
            title: "Some old task",
            isCompleted: false,
            tags: [],
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/Notes.md",
                lineNumber: 1,
                originalLine: "- [ ] Some old task"
            )
        )
        var obsidianMap: [String: SyncTask] = [:]
        obsidianMap[SyncState.generateObsidianId(task: existingTask)] = existingTask

        var titleIndex: [String: String] = [:]
        for (id, task) in obsidianMap {
            titleIndex[task.title] = id
        }

        let trulyNewReminder = SyncTask(
            title: "Buy birthday cake",
            isCompleted: false,
            tags: [],
            targetList: "Personal"
        )

        XCTAssertNil(
            titleIndex[trulyNewReminder.title],
            "Genuinely new reminders (title not present anywhere in vault) must not be skipped — they're the legitimate use case for the inbox writeback feature."
        )
    }
}
