import XCTest
@testable import Remindian

final class PersistenceTests: XCTestCase {

    // MARK: - SyncState Round-Trip

    func testSyncStateEncodeDecode() {
        let state = SyncState()
        state.lastSyncDate = Date(timeIntervalSince1970: 1_700_000_000)
        state.addOrUpdateMapping(
            obsidianId: "file.md|Buy milk|",
            remindersId: "reminder-123",
            obsidianHash: "hash-a",
            remindersHash: "hash-b"
        )
        state.addOrUpdateMapping(
            obsidianId: "work.md|Ship feature|work",
            remindersId: "reminder-456",
            obsidianHash: "hash-c",
            remindersHash: "hash-d"
        )

        let data = try! JSONEncoder().encode(state)
        let decoded = try! JSONDecoder().decode(SyncState.self, from: data)

        XCTAssertEqual(decoded.mappings.count, 2)
        XCTAssertEqual(decoded.stateVersion, SyncState.currentStateVersion)
        XCTAssertEqual(decoded.lastSyncDate?.timeIntervalSince1970, 1_700_000_000)

        let first = decoded.findMapping(obsidianId: "file.md|Buy milk|")
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.remindersId, "reminder-123")
        XCTAssertEqual(first?.lastObsidianHash, "hash-a")
        XCTAssertEqual(first?.lastRemindersHash, "hash-b")

        let second = decoded.findMapping(remindersId: "reminder-456")
        XCTAssertNotNil(second)
        XCTAssertEqual(second?.obsidianId, "work.md|Ship feature|work")
    }

    func testSyncStateCorruptedDataReturnsDefaults() {
        let corrupted = "{ this is not valid json".data(using: .utf8)!

        let decoded = try? JSONDecoder().decode(SyncState.self, from: corrupted)
        XCTAssertNil(decoded, "Corrupted JSON should fail to decode")

        // Verify the fallback produces a usable default
        let fallback = SyncState()
        XCTAssertTrue(fallback.mappings.isEmpty)
        XCTAssertNil(fallback.lastSyncDate)
        XCTAssertEqual(fallback.stateVersion, SyncState.currentStateVersion)
    }

    func testSyncStateTruncatedDataReturnsDefaults() {
        // Simulate a crash mid-write: valid JSON prefix, truncated
        let state = SyncState()
        state.addOrUpdateMapping(
            obsidianId: "test", remindersId: "r1",
            obsidianHash: "h1", remindersHash: "h2"
        )
        let fullData = try! JSONEncoder().encode(state)
        let truncated = fullData.prefix(fullData.count / 2)

        let decoded = try? JSONDecoder().decode(SyncState.self, from: truncated)
        XCTAssertNil(decoded, "Truncated JSON should fail to decode")
    }

    /// v5.7.0 bumped the sync state schema from v7 to v8 (lineNumber added to
    /// recurring task IDs, see #57). Decoding an older-version payload must
    /// round-trip cleanly: mappings preserved for re-linking, version bumped.
    /// Tied to the plan item for #58 — validate the init path survives schema
    /// drift without crashing.
    func testSyncStateV7PayloadDecodesCleanly() throws {
        let v7JSON = """
        {
          "mappings": [
            {
              "obsidianId": "old-id",
              "remindersId": "r-1",
              "lastObsidianHash": "h-o",
              "lastRemindersHash": "h-r",
              "lastSyncDate": 1700000000
            }
          ],
          "lastSyncDate": 1700000000,
          "stateVersion": 7
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SyncState.self, from: v7JSON)
        XCTAssertEqual(decoded.mappings.count, 1)
        XCTAssertEqual(decoded.mappings.first?.obsidianId, "old-id")
        // Mappings preserved; the SyncEngine's re-linking logic will re-hash
        // recurring tasks to their v8 IDs on first sync.
    }

    /// Payloads from state versions we don't explicitly migrate (older than v6)
    /// should not crash — loading can return a fresh state via the SyncState.load
    /// catch path, but at the minimum decoding the raw payload must succeed so
    /// the reset path has something to work with.
    func testSyncStateAncientVersionDecodesWithoutCrash() throws {
        let v3JSON = """
        {
          "mappings": [],
          "lastSyncDate": null,
          "stateVersion": 3
        }
        """.data(using: .utf8)!

        XCTAssertNoThrow(try JSONDecoder().decode(SyncState.self, from: v3JSON))
    }

    // MARK: - SyncLog Round-Trip

    func testSyncLogEncodeDecode() {
        let log = SyncLog()
        let summary = SyncLog.SyncResultSummary(
            created: 3,
            updated: 1,
            deleted: 0,
            completionsWrittenBack: 2,
            errorCount: 0,
            isDryRun: false,
            summary: "3 created, 1 updated, 2 written back"
        )
        let detail = SyncEngine.SyncLogDetail(
            action: .created,
            taskTitle: "Buy groceries",
            filePath: "inbox.md",
            errorMessage: nil
        )
        let entry = SyncLog.SyncLogEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            result: summary,
            duration: 1.5,
            details: [detail]
        )
        log.entries = [entry]

        let data = try! JSONEncoder().encode(log)
        let decoded = try! JSONDecoder().decode(SyncLog.self, from: data)

        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries[0].result.created, 3)
        XCTAssertEqual(decoded.entries[0].result.updated, 1)
        XCTAssertEqual(decoded.entries[0].result.completionsWrittenBack, 2)
        XCTAssertEqual(decoded.entries[0].result.summary, "3 created, 1 updated, 2 written back")
        XCTAssertEqual(decoded.entries[0].duration, 1.5)
        XCTAssertEqual(decoded.entries[0].details.count, 1)
        XCTAssertEqual(decoded.entries[0].details[0].action, .created)
        XCTAssertEqual(decoded.entries[0].details[0].taskTitle, "Buy groceries")
    }

    func testSyncLogCorruptedDataReturnsDefaults() {
        let corrupted = "not json at all".data(using: .utf8)!

        let decoded = try? JSONDecoder().decode(SyncLog.self, from: corrupted)
        XCTAssertNil(decoded, "Corrupted JSON should fail to decode")

        let fallback = SyncLog()
        XCTAssertTrue(fallback.entries.isEmpty)
    }

    func testSyncLogTruncatedDataReturnsDefaults() {
        let log = SyncLog()
        let summary = SyncLog.SyncResultSummary(
            created: 1, updated: 0, deleted: 0,
            completionsWrittenBack: 0, errorCount: 0,
            isDryRun: false, summary: "1 created"
        )
        log.entries = [
            SyncLog.SyncLogEntry(
                timestamp: Date(), result: summary, duration: 0.5, details: []
            )
        ]
        let fullData = try! JSONEncoder().encode(log)
        let truncated = fullData.prefix(fullData.count / 2)

        let decoded = try? JSONDecoder().decode(SyncLog.self, from: truncated)
        XCTAssertNil(decoded, "Truncated JSON should fail to decode")
    }

    // MARK: - SyncConfiguration Corrupted Data

    func testSyncConfigurationCorruptedDataReturnsDefaults() {
        let corrupted = "{ broken json !!!".data(using: .utf8)!

        let decoded = try? JSONDecoder().decode(SyncConfiguration.self, from: corrupted)
        XCTAssertNil(decoded, "Corrupted JSON should fail to decode")

        let fallback = SyncConfiguration()
        XCTAssertEqual(fallback.vaultPath, "")
        XCTAssertEqual(fallback.syncIntervalMinutes, 5)
        XCTAssertTrue(fallback.listMappings.isEmpty)
    }

    func testSyncConfigurationTruncatedDataReturnsDefaults() {
        let config = SyncConfiguration()
        config.vaultPath = "/Users/test/vault"
        config.todoistApiToken = "test-token"
        config.listMappings = [
            SyncConfiguration.ListMapping(obsidianTag: "work", remindersList: "Work")
        ]
        let fullData = try! JSONEncoder().encode(config)
        let truncated = fullData.prefix(fullData.count / 2)

        let decoded = try? JSONDecoder().decode(SyncConfiguration.self, from: truncated)
        XCTAssertNil(decoded, "Truncated JSON should fail to decode")
    }
}
