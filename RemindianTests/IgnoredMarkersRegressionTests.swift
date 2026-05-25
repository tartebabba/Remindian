import XCTest
@testable import Remindian

/// Regression tests for v5.10.1 — issue #70 (itauberg).
///
/// **Feature.** Some users adopt extended checkbox markers like `[i]` for
/// "informational" entries that look like task lines but should NOT sync as
/// reminders. v5.9.0 (#63) added open / completed marker configurability;
/// this issue asks for a third category — "ignore this line entirely".
///
/// **Implementation.** A new `obsidianTasksIgnoredMarkers` config field +
/// matching `ignoredMarkers: Set<Character>` parameter on
/// `SyncTask.fromObsidianLine`. When the checkbox marker appears in the
/// ignored set, the parser returns `nil` (treats the line as a non-task).
///
/// If a marker is in both ignored AND open/completed, ignored wins — that's
/// the safer default (user-intent: "really, don't touch this").
final class IgnoredMarkersRegressionTests: XCTestCase {

    // MARK: - Core behavior

    func test_70_ignoredMarkerReturnsNil() {
        let task = SyncTask.fromObsidianLine(
            "- [i] This is informational, not a task",
            filePath: "/note.md",
            lineNumber: 1,
            ignoredMarkers: ["i"]
        )
        XCTAssertNil(
            task,
            "A line with an ignored marker must parse as nil — the sync engine should never see it. (#70)"
        )
    }

    func test_70_sameMarkerWithoutIgnoredConfigStillParses() {
        // Back-compat: same input, no ignored config → still parses as a task
        // (with default open classification). Guarantees we didn't accidentally
        // break the v5.9.0 unknown-marker → open fallback.
        let task = SyncTask.fromObsidianLine(
            "- [i] This is informational, not a task",
            filePath: "/note.md",
            lineNumber: 1
        )
        XCTAssertNotNil(task, "Without an ignored config, the v5.9.0 lenient parser still treats `[i]` as a task.")
        XCTAssertEqual(task?.isCompleted, false, "Unknown markers default to open.")
    }

    func test_70_ignoredBeatsOpenOnConflict() {
        // If the user puts the same marker in both lists, ignored wins.
        // This is the safer default — "don't sync" is a stronger intent than
        // "treat as open".
        let task = SyncTask.fromObsidianLine(
            "- [i] Should be ignored even though it's also in openMarkers",
            filePath: "/note.md",
            lineNumber: 1,
            openMarkers: [" ", "i"],
            ignoredMarkers: ["i"]
        )
        XCTAssertNil(
            task,
            "Ignored set wins over open set on the same marker — that's the documented precedence. (#70)"
        )
    }

    func test_70_ignoredBeatsCompletedOnConflict() {
        // Same precedence rule on the other side.
        let task = SyncTask.fromObsidianLine(
            "- [-] Cancelled in some workflows but ignored here",
            filePath: "/note.md",
            lineNumber: 1,
            completedMarkers: ["x", "X", "-"],
            ignoredMarkers: ["-"]
        )
        XCTAssertNil(task, "Ignored beats completed too — symmetric precedence.")
    }

    func test_70_normalOpenAndCompletedStillWorkWithIgnoredConfigured() {
        // Sanity: configuring an ignored marker doesn't break the standard
        // `[ ]` / `[x]` paths.
        let open = SyncTask.fromObsidianLine(
            "- [ ] Regular task",
            filePath: "/t.md",
            lineNumber: 1,
            ignoredMarkers: ["i", "_"]
        )
        XCTAssertNotNil(open)
        XCTAssertEqual(open?.isCompleted, false)

        let done = SyncTask.fromObsidianLine(
            "- [x] Regular completion",
            filePath: "/t.md",
            lineNumber: 1,
            ignoredMarkers: ["i", "_"]
        )
        XCTAssertNotNil(done)
        XCTAssertEqual(done?.isCompleted, true)
    }

    func test_70_multipleIgnoredMarkersAllRespected() {
        let ignored: Set<Character> = ["i", "_", "?"]

        for marker in ignored {
            let task = SyncTask.fromObsidianLine(
                "- [\(marker)] line",
                filePath: "/t.md",
                lineNumber: 1,
                ignoredMarkers: ignored
            )
            XCTAssertNil(task, "Marker [\(marker)] should be ignored.")
        }
    }

    // MARK: - End-to-end through ObsidianService

    func test_70_ignoredMarkerSkippedDuringVaultScan() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("remindian-70-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let content = """
        # Notes

        - [ ] Real task #work
        - [i] Just an info line
        - [x] Already done #work
        - [i] Another info line
        - [ ] Another real task #work
        """
        let fileURL = vault.appendingPathComponent("Note.md")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let tasks = try ObsidianService().parseTasksFromFile(
            fileURL,
            vaultPath: vault.path,
            ignoredMarkers: ["i"]
        )

        XCTAssertEqual(tasks.count, 3, "Only the 3 non-ignored lines should become tasks.")
        XCTAssertEqual(tasks.map(\.title), ["Real task", "Already done", "Another real task"])
    }

    // MARK: - Config persistence

    func test_70_codableRoundtripPreservesIgnoredMarkers() throws {
        let original = SyncConfiguration(obsidianTasksIgnoredMarkers: ["i", "_"])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncConfiguration.self, from: encoded)
        XCTAssertEqual(decoded.obsidianTasksIgnoredMarkers, ["i", "_"])
    }

    /// Pre-v5.10.1 configs don't have the `obsidianTasksIgnoredMarkers` key.
    /// They must decode cleanly with an empty default — preserving v5.10.0
    /// behavior exactly for users upgrading.
    func test_70_preV510_1ConfigDecodesWithEmptyDefault() throws {
        let legacyJSON = """
        {
          "vaultPath": "/tmp/vault",
          "syncIntervalMinutes": 5,
          "enableAutoSync": false,
          "syncOnLaunch": true,
          "listMappings": [],
          "defaultList": "Reminders",
          "taskFilesPattern": "**/*.md",
          "excludedFolders": [".obsidian"],
          "syncCompletedTasks": true,
          "conflictResolution": "obsidian",
          "obsidianTasksOpenMarkers": [" "],
          "obsidianTasksCompletedMarkers": ["x", "X"]
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let config = try JSONDecoder().decode(SyncConfiguration.self, from: data)
        XCTAssertTrue(
            config.obsidianTasksIgnoredMarkers.isEmpty,
            "Pre-v5.10.1 configs decode with empty ignored list — full v5.10.0 compatibility. (#70)"
        )
    }
}
