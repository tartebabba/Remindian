import XCTest
import EventKit
@testable import Remindian

/// Regression tests for v5.10.0 — issue #69 (Gouryella91).
///
/// **Bug.** Every reminder created from a task with `addTaskLinkToReminders =
/// true` got the obsidian:// URL written to BOTH `reminder.url` AND appended
/// into `reminder.notes`. Apple Reminders renders the URL field as a single
/// clickable Obsidian icon, so the notes-side copy was just visual clutter
/// (a long percent-encoded line in every reminder).
///
/// **Fix.** Make the notes-side append opt-in via a new
/// `appendTaskLinkToNotes` setting that defaults to `false`. The URL field
/// remains driven by the existing `addTaskLinkToReminders` toggle. Users
/// upgrading from v5.9.x get the cleaner display on their next sync; users
/// who actually use a client that doesn't display URL fields can re-enable.
///
/// These tests don't need EventKit access — they construct an `EKReminder`
/// in an in-memory `EKEventStore` instance and inspect the `url` / `notes`
/// fields directly. No system-level reminder access happens.
final class ObsidianURIHandlingTests: XCTestCase {

    private var store: EKEventStore!

    override func setUp() {
        super.setUp()
        store = EKEventStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    private func makeTask() -> SyncTask {
        SyncTask(
            title: "Test task",
            isCompleted: false,
            tags: [],
            obsidianSource: SyncTask.ObsidianSource(
                filePath: "/Work.md",
                lineNumber: 3,
                originalLine: "- [ ] Test task"
            )
        )
    }

    private func makeReminder() -> EKReminder {
        EKReminder(eventStore: store)
    }

    // MARK: - Default behavior (v5.10 — clean notes)

    /// Default behavior since v5.10: URL is set on `reminder.url`, NOT
    /// duplicated in notes. This is the entire point of #69.
    func test_cleanByDefault_urlSetButNotesDoNotContainURL() {
        let task = makeTask()
        let reminder = makeReminder()

        task.applyToReminder(
            reminder,
            includeDueTime: false,
            addTaskLink: true,        // user wants the URL link
            vaultPath: "/tmp/MyVault",
            appendLinkToNotes: false  // v5.10 default
        )

        XCTAssertNotNil(reminder.url, "URL field must still be set — that's the clickable icon in Reminders.")
        XCTAssertEqual(reminder.url?.scheme, "obsidian")

        let notes = reminder.notes ?? ""
        XCTAssertFalse(
            notes.contains("obsidian://"),
            "URL must NOT appear in notes by default — that's the noise #69 was about to remove."
        )
    }

    // MARK: - Opt-in append (legacy / older-client path)

    func test_appendToNotesOptIn_urlAppearsInBoth() {
        let task = makeTask()
        let reminder = makeReminder()

        task.applyToReminder(
            reminder,
            includeDueTime: false,
            addTaskLink: true,
            vaultPath: "/tmp/MyVault",
            appendLinkToNotes: true   // user opted in via Settings
        )

        XCTAssertNotNil(reminder.url, "URL field still set.")
        XCTAssertEqual(reminder.url?.scheme, "obsidian")

        let notes = reminder.notes ?? ""
        XCTAssertTrue(
            notes.contains("obsidian://"),
            "When appendLinkToNotes is true, the URL must also appear in notes (legacy-client path)."
        )
    }

    // MARK: - No link at all

    func test_noLinkAtAllWhenAddTaskLinkOff() {
        let task = makeTask()
        let reminder = makeReminder()

        task.applyToReminder(
            reminder,
            includeDueTime: false,
            addTaskLink: false,       // master switch off
            vaultPath: "/tmp/MyVault",
            appendLinkToNotes: true   // ignored when addTaskLink is false
        )

        XCTAssertNil(reminder.url, "URL field stays nil when addTaskLink is off.")
        let notes = reminder.notes ?? ""
        XCTAssertFalse(
            notes.contains("obsidian://"),
            "appendLinkToNotes is meaningless when addTaskLink is off — no link should appear anywhere."
        )
    }

    // MARK: - Config decoding migration (pre-v5.10 → v5.10)

    /// A serialized config from v5.9.x doesn't have the
    /// `appendTaskLinkToNotes` key. The `decodeIfPresent ?? false` fallback
    /// must produce `false` so existing users automatically get the cleaner
    /// behavior without touching settings.
    func test_preV510ConfigDecodesWithCleanDefault() throws {
        let legacyJSON = """
        {
          "vaultPath": "/tmp/vault",
          "syncIntervalMinutes": 5,
          "enableAutoSync": false,
          "syncOnLaunch": true,
          "listMappings": [],
          "defaultList": "Reminders",
          "taskFilesPattern": "**/*.md",
          "excludedFolders": [".obsidian", ".git", ".trash"],
          "syncCompletedTasks": true,
          "conflictResolution": "obsidian",
          "addTaskLinkToReminders": true
        }
        """

        let data = legacyJSON.data(using: .utf8)!
        let config = try JSONDecoder().decode(SyncConfiguration.self, from: data)

        XCTAssertTrue(config.addTaskLinkToReminders, "Existing toggle preserved.")
        XCTAssertFalse(
            config.appendTaskLinkToNotes,
            "Pre-v5.10 configs must decode with the new field defaulting to false — the migration story for #69."
        )
    }

    /// Roundtrip: encode then decode preserves the toggle. Guards against an
    /// asymmetry where we add the encode but forget the decode (or vice versa).
    func test_appendTaskLinkToNotesSurvivesCodableRoundtrip() throws {
        let original = SyncConfiguration(appendTaskLinkToNotes: true)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncConfiguration.self, from: encoded)
        XCTAssertTrue(decoded.appendTaskLinkToNotes)

        let original2 = SyncConfiguration(appendTaskLinkToNotes: false)
        let encoded2 = try JSONEncoder().encode(original2)
        let decoded2 = try JSONDecoder().decode(SyncConfiguration.self, from: encoded2)
        XCTAssertFalse(decoded2.appendTaskLinkToNotes)
    }
}
