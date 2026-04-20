import Foundation

/// Tracks the relationship between Obsidian tasks and Apple Reminders.
/// Used to detect changes and handle conflicts.
class SyncState: Codable {
    var mappings: [TaskMapping]
    var lastSyncDate: Date?
    var stateVersion: Int

    /// Current version of the ID generation scheme.
    /// Bump this when the ID format changes to trigger auto-reset.
    /// v2: content-hash IDs. v3: clean titles + client from frontmatter.
    /// v4: client from YAML frontmatter. v5: tags in notes + auto list mapping.
    /// v6: fixed recurrence start date from "on the Nth" rules.
    /// v7: stable IDs — removed mutable fields (dates, priority) from obsidianId
    ///     to prevent delete+recreate on metadata changes. Re-linking in sync engine
    ///     handles the migration gracefully.
    /// v8: recurring tasks include lineNumber in obsidianId so the completed copy
    ///     and the new-uncompleted copy that Obsidian Tasks plugin inserts get
    ///     distinct IDs. Fixes #57 scenarios 1 & 2 (duplicates / missed occurrences
    ///     when completing in Obsidian or Reminders). Non-recurring tasks keep
    ///     content-stable IDs (no lineNumber) so reordering still doesn't break
    ///     mappings.
    static let currentStateVersion = 8

    struct TaskMapping: Codable, Identifiable {
        var id: String { obsidianId }
        let obsidianId: String
        let remindersId: String
        var lastObsidianHash: String
        var lastRemindersHash: String
        var lastSyncDate: Date

        func hasObsidianChanged(currentHash: String) -> Bool {
            return currentHash != lastObsidianHash
        }

        func hasRemindersChanged(currentHash: String) -> Bool {
            return currentHash != lastRemindersHash
        }
    }

    init() {
        self.mappings = []
        self.lastSyncDate = nil
        self.stateVersion = Self.currentStateVersion
    }

    // MARK: - Persistence

    private static var stateURL: URL? {
        guard let appFolder = remindianAppSupportDir() else { return nil }
        return appFolder.appendingPathComponent("sync_state.json")
    }

    func save() {
        guard let url = Self.stateURL else { return }
        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save sync state: \(error)")
        }
    }

    static func load() -> SyncState {
        do {
            guard let url = stateURL else { return SyncState() }
            let data = try Data(contentsOf: url)
            let state = try JSONDecoder().decode(SyncState.self, from: data)

            // Handle state version migrations
            if state.stateVersion < currentStateVersion {
                if state.stateVersion == 6 || state.stateVersion == 7 {
                    // v6 → v7: ObsidianId format changed (removed mutable fields).
                    // v7 → v8: Recurring tasks now include lineNumber in their ID.
                    //   Non-recurring tasks keep stable IDs — only recurring ones
                    //   get new IDs, and those are rare. Re-linking in the sync
                    //   engine matches by title, so existing mappings gracefully
                    //   transition without deleting/recreating destination tasks.
                    print("Sync state v\(state.stateVersion) → v\(currentStateVersion): ID format migration. Keeping mappings for re-linking.")
                    state.stateVersion = currentStateVersion
                    state.save()
                } else {
                    // Older versions: full reset
                    print("Sync state version outdated (v\(state.stateVersion) → v\(currentStateVersion)). Resetting sync state for re-sync.")
                    let fresh = SyncState()
                    fresh.save()
                    return fresh
                }
            }

            return state
        } catch {
            return SyncState()
        }
    }

    // MARK: - Mapping Management

    func findMapping(obsidianId: String) -> TaskMapping? {
        return mappings.first { $0.obsidianId == obsidianId }
    }

    func findMapping(remindersId: String) -> TaskMapping? {
        return mappings.first { $0.remindersId == remindersId }
    }

    func addOrUpdateMapping(obsidianId: String, remindersId: String, obsidianHash: String, remindersHash: String) {
        if let index = mappings.firstIndex(where: { $0.obsidianId == obsidianId }) {
            mappings[index] = TaskMapping(
                obsidianId: obsidianId,
                remindersId: remindersId,
                lastObsidianHash: obsidianHash,
                lastRemindersHash: remindersHash,
                lastSyncDate: Date()
            )
        } else {
            mappings.append(TaskMapping(
                obsidianId: obsidianId,
                remindersId: remindersId,
                lastObsidianHash: obsidianHash,
                lastRemindersHash: remindersHash,
                lastSyncDate: Date()
            ))
        }
    }

    func removeMapping(obsidianId: String) {
        mappings.removeAll { $0.obsidianId == obsidianId }
    }

    func removeMapping(remindersId: String) {
        mappings.removeAll { $0.remindersId == remindersId }
    }

    // MARK: - Hash Generation

    /// Generate a stable ID from task content.
    ///
    /// - **Non-recurring tasks:** hash of `filePath + title + tags` (no line number).
    ///   Stable across line reordering. NOT including dates/priority/completion
    ///   (mutable fields that change independently and would cause delete+recreate
    ///   instead of in-place update).
    ///
    /// - **Recurring tasks (task.recurrenceRule != nil):** hash also includes the
    ///   `lineNumber`. The Obsidian Tasks plugin inserts a new line for each new
    ///   occurrence (e.g. after completing `- [x] Pay rent 🔁 every month` it adds
    ///   `- [ ] Pay rent 🔁 every month` above it). Without lineNumber in the hash,
    ///   both lines collide on the same obsidianId — the second one overwrites the
    ///   first in the obsidianMap, and sync misbehaves (scenarios 1 & 2 in #57).
    ///   Including lineNumber gives them distinct IDs; the same-file dedup pass
    ///   in SyncEngine then correctly keeps the uncompleted one and drops the
    ///   completed one.
    ///
    /// Reordering a recurring task changes its ID, which orphans the old mapping —
    /// the sync engine's re-linking logic reattaches it by title. This is an
    /// acceptable trade-off: recurring tasks get reordered rarely, and the
    /// alternative (missed occurrences + duplicate creation) is worse.
    static func generateObsidianId(task: SyncTask) -> String {
        guard let source = task.obsidianSource else {
            // Fallback: use title-based ID
            let components = [task.title, task.targetList ?? ""]
            return components.joined(separator: "|").data(using: .utf8)?.base64EncodedString() ?? ""
        }
        var components = [
            source.filePath,
            task.title,
            task.tags.sorted().joined(separator: ",")
        ]
        if task.recurrenceRule != nil {
            // Recurring: disambiguate by line so completed + new uncompleted copies
            // don't collapse to a single map entry. See #57.
            components.append("L\(source.lineNumber)")
        }
        return components.joined(separator: "|").data(using: .utf8)?.base64EncodedString() ?? ""
    }

    /// Generate a hash of all task fields to detect any changes.
    static func generateTaskHash(_ task: SyncTask) -> String {
        let components = [
            task.title,
            String(task.isCompleted),
            String(task.priority.rawValue),
            task.dueDate?.ISO8601Format() ?? "",
            task.startDate?.ISO8601Format() ?? "",
            task.scheduledDate?.ISO8601Format() ?? "",
            task.completedDate?.ISO8601Format() ?? "",
            task.targetList ?? "",
            task.tags.sorted().joined(separator: ",")
        ]
        return components.joined(separator: "|").data(using: .utf8)?.base64EncodedString() ?? ""
    }
}
