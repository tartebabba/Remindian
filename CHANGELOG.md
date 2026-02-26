# Changelog

All notable changes to Remindian (formerly Obsync) are documented here.

---

## v3.5.0 (February 2026)

### New Features
- **Configurable field mapping for TaskNotes** — Map your YAML frontmatter field names to Remindian properties. If your TaskNotes uses custom fields (e.g., `deadline` instead of `due`, `importance` instead of `priority`), configure the mapping in Settings > Advanced > TaskNotes > Field Mapping (#19)
- **Project/context as Reminders list** — Choose which TaskNotes field determines the Reminders list/folder: `tags` (default), `project`, or `context`. Supports wikilinks (e.g., `project: [[My Project]]` → "My Project" list). Configurable in Settings > Advanced > TaskNotes > List/Folder Source (#20)
- **GoodTask tag writeback** — Tag changes in Reminders (e.g., via GoodTask's Kanban board) sync back to Obsidian `#tags`. Enable in Settings > General > Sync tag changes (#17)
- **Exclude Reminders lists** — Blacklist specific Reminders lists from sync (e.g., Groceries, Shared). Easier to manage than the whitelist when you only want to skip a few lists. Configure in Settings > Advanced > Reminders List Filtering (#21)

### Bug Fixes
- Fixed: Task completed in Obsidian (`- [x]`) was being reverted to incomplete on next sync when Reminders still showed it as incomplete. Source of truth (Obsidian) now correctly wins — Reminders is updated to match (#16)
- Fixed: Settings window too small and couldn't be resized — now resizable with scroll support in Advanced tab (#18)

### Technical Changes
- `TaskNotesFieldMapping` struct for configurable YAML field names (title, status, priority, due, scheduled, completedDate, tags, project, context)
- `SyncConfiguration` gains `taskNotesFieldMapping`, `taskNotesListField`, `excludedRemindersLists`, `enableTagWriteback` fields
- `TaskNotesSource` uses `fieldMapping` for all YAML read/write operations instead of hardcoded field names
- `TaskNotesSource` uses `listField` to determine `targetList` from project/context/tags/custom field
- `MtnCliTask` and `TaskNotesApiTask` gain `project`/`context` fields and `listField` parameter
- `stripWikilinks()` helper removes `[[` and `]]` brackets from field values
- `SyncEngine` completion sync direction fixed: when `oTask.isCompleted && !rTask.isCompleted`, sets `taskForReminders.isCompleted = true`
- `SyncEngine` filters excluded Reminders lists in both Step 2 (fetch) and Step 5 (creation)
- `MetadataChanges.newTags` enables tag writeback; `applyTagChange()` added to `ObsidianService`
- Settings window uses `minWidth`/`minHeight` with `idealWidth`/`idealHeight` for resizable layout

---

## v3.4.0 (February 2026)

### New Features
- **Custom status mapping for TaskNotes** — Configure which status values mean "completed" (e.g., `done`, `completed`, `cancelled`, `archived`, `shipped`). Also set custom status values for marking tasks complete/incomplete from Reminders. Configurable in Settings > Advanced > TaskNotes (#10)
- **Support for + prefix in list mappings** — Tasks tagged with `+Project` now map to Reminders lists just like `#tag`. Both `#` and `+` prefixes are supported (#14)

### Bug Fixes
- Fixed: List items with wikilinks (e.g., `- [[Sarah]] coming to stay`) were incorrectly parsed as tasks and created Reminders. Now only proper checkbox items (`- [ ]` / `- [x]`) are recognized (#13)

### Improvements (cherry-picked from [PR #8](https://github.com/Santofer/Remindian/pull/8) by [@tparsons9](https://github.com/tparsons9))
- **Flexible API response parsing** — HTTP API now supports wrapped responses (`{ success, data: [...] }`) and collection envelopes (`{ data: { tasks: [...] } }`), improving compatibility with different TaskNotes plugin versions
- **Better HTTP error handling** — API calls now check HTTP status codes and provide detailed error messages with response snippets
- **Smarter notification permissions** — Checks authorization status before prompting; logs detailed errors for denied or failed permission requests
- **Source/destination refresh before sync** — Ensures latest config settings (API URL, status mapping, etc.) are always used

### Technical Changes
- `SyncConfiguration` gains `taskNotesCompletedStatuses`, `taskNotesOpenStatus`, `taskNotesDoneStatus` fields
- Task checkbox detection now uses strict prefix matching (`- [ ] ` or `- [x] `) instead of loose `- [` prefix
- Tag regex updated from `#[\w-]+` to `[#+][\w-]+` to support both prefixes
- `remindersListForTag()` strips both `#` and `+` prefixes when matching
- `TaskNotesSource` uses configurable status mapping instead of hardcoded values
- `MtnCliTask.toSyncTask()` and `TaskNotesApiTask.toSyncTask()` accept `completedStatuses` parameter
- `TaskNotesApiEnvelope` and `TaskNotesApiTaskCollection` models added for flexible JSON decoding
- `NotificationService.requestPermission()` checks `getNotificationSettings` before requesting
- `SyncManager.performSync()` calls `updateSourceAndDestination()` to pick up config changes

---

## v3.3.0 (February 2026)

### New Features
- **Universal Binary (Intel + Apple Silicon)** — DMG now includes both arm64 and x86_64 architectures, fixing compatibility with Intel Macs (#7)
- **Launch at Login** — Option to automatically start Remindian when you log in (Settings > Appearance & Shortcuts)
- **Skip old completed tasks** — Configurable age limit to prevent syncing thousands of old completed tasks. Choose 7/30/90/180/365 days (#11)
- **Reminders list filtering** — Only sync specific Reminders lists (e.g., "Work, Personal") instead of all lists. Great for excluding shared lists like Groceries (#12)
- **Task link in Reminders** — Adds an `obsidian://` deep link in Reminders notes so you can jump directly to the task file (#9)

### Bug Fixes
- Fixed: DMG not working on Intel Macs — was arm64-only (#7)

### Technical Changes
- Build configuration now uses `ARCHS = $(ARCHS_STANDARD)` for universal binary output
- `SMAppService.mainApp` used for launch-at-login (macOS 13+)
- `SyncConfiguration` gains `launchAtLogin`, `maxCompletedTaskAgeDays`, `syncedRemindersLists`, `addTaskLinkToReminders` fields
- `SyncEngine` filters completed tasks by age before sync
- `SyncEngine` filters destination tasks by allowed Reminders lists
- `applyToReminder()` now optionally adds `obsidian://open` URL to notes

---

## v3.2.0 (February 2026)

### New Features
- **TaskNotes CLI integration (`mtn`)** — Sync tasks using the [mdbase-tasknotes](https://github.com/callumalpass/mdbase-tasknotes) CLI tool. Works completely standalone without Obsidian open. Install with `npm install -g mdbase-tasknotes`
- **TaskNotes integration mode picker** — Choose between CLI (mtn), Direct Files, or HTTP API in Settings
- **Auto-updater** — Checks GitHub Releases for new versions automatically (every 24 hours). Downloads, mounts DMG, replaces the app, and relaunches — all without opening a browser
- **Buy Me a Coffee** — Support the project directly from the About page

### Technical Changes
- `TaskNotesSource` now supports 3 integration modes: CLI (`mtn list --json`), file-based (direct YAML parsing), and HTTP API
- CLI mode uses `Process` to invoke `mtn` with auto-detection of the binary path
- All CLI operations: scan (`mtn list --json`), complete (`mtn complete`), update (`mtn update`), create (`mtn create`)
- File-based mode updated to match mdbase-tasknotes field names (`scheduled` instead of `start`, `completedDate`, `title` in frontmatter)
- `SyncConfiguration` gains `taskNotesIntegrationMode` field (backward compatible, defaults to `cli`)
- `UpdaterService` checks GitHub Releases API, downloads DMG, mounts with `hdiutil`, replaces app bundle, and relaunches
- About page redesigned with update status, progress bar, and Buy Me a Coffee button

---

## v3.1.0-beta (February 2026)

### New Features
- **Things 3 integration** — Sync your tasks to [Things 3](https://culturedcode.com/things/) instead of (or in addition to) Apple Reminders. Reads tasks via AppleScript, creates/updates via `things://` URL scheme
- **TaskNotes integration** — Use the [TaskNotes](https://github.com/nicolo/obsidian-tasknotes) Obsidian plugin as a task source. Parses YAML frontmatter files (one file per task) with support for status, priority, due/start dates, tags, and recurrence
- **Modular architecture** — New `TaskSource` / `TaskDestination` protocol system. The sync engine is now source/destination agnostic, making it easy to add more backends in the future
- **Source & Destination picker** — Choose your task source (Obsidian Tasks or TaskNotes) and destination (Apple Reminders or Things 3) in Settings and in the onboarding wizard
- **FileWatcher self-change filtering** — Writes made by Remindian itself no longer trigger a redundant re-sync (prevents feedback loops)
- **Safety abort** — Sync aborts automatically if the source task count drops more than 50% compared to existing mappings (protects against vault unmounted, scan failures, etc.)
- **Content-hash task IDs** — Task IDs no longer include line numbers, making them stable across line reordering in Obsidian files
- **Unit test suite** — 34 automated tests covering task parsing, deduplication, TaskNotes parsing, and configuration management

### Technical Changes
- `SyncEngine` now takes `TaskSource` and `TaskDestination` protocols instead of direct service instances
- `SyncManager` uses factory methods to create source/destination at runtime based on user settings
- `Things3Destination` handles reading (AppleScript), creating (URL scheme), updating (URL scheme + auth token), and deleting (AppleScript)
- `TaskNotesSource` parses YAML frontmatter and supports both file-based scanning and HTTP API (localhost:7117)
- `RemindersDestination` wraps EventKit behind the `TaskDestination` protocol
- `ObsidianTasksSource` wraps `ObsidianService` behind the `TaskSource` protocol
- `FileWatcherService` now maintains a `selfModifiedFiles` set with 3-second auto-expiry for change filtering
- Added `NSAppleEventsUsageDescription` to Info.plist for Things 3 AppleScript access
- Onboarding wizard expanded to 6 steps (new "Choose Your Setup" step)
- Settings view updated with Source & Destination section and conditional fields

---

## v3.0.0-beta (February 2026) — Remindian

**App renamed from Obsync to Remindian.**

### New Features
- **Due date writeback** — Changes to due dates in Reminders sync back to Obsidian (`📅`)
- **Start date writeback** — Changes to start dates in Reminders sync back to Obsidian (`🛫`)
- **Priority writeback** — Changes to priority in Reminders sync back to Obsidian (`⏫`/`🔼`/`🔽`)
- **New task writeback** — Tasks created in Reminders are appended to an Obsidian inbox file
- **Recurrence writeback** — Completing a recurring task in Reminders creates the next occurrence in Obsidian with correctly computed dates
- **FSEvents file watcher** — Real-time sync triggered by vault file changes (optional)
- **Onboarding wizard** — Guided setup on first launch with folder filtering and tag mapping configuration
- **Folder whitelist** — Optionally scan only specific vault folders instead of the entire vault
- **Cross-file deduplication** — Detects duplicate tasks across files (e.g. Inbox.md + original) and syncs only one copy
- **About page** — In-app version info, author credits, update check link
- **Config persistence fix** — Settings (exclusions, mappings, whitelist) now save correctly when modified
- **Consistent menu bar font** — All menu items use the same system font size

### Bug Fixes
- **Fixed emoji encoding corruption** — `applyDateChange()` rewritten to only replace date digits (YYYY-MM-DD), preserving original emoji bytes verbatim
- **Fixed FE0F variation selector handling** — All emoji regex patterns now include `\u{FE0F}?` to handle optional Unicode variation selectors
- **Fixed recurrence text leaking into titles** — Both emoji-based (`🔁`) and plain-text (`every month on the 1st when done`) recurrence rules are now stripped from task titles
- **Fixed recurrence writeback line-shift corruption** — Line offset tracking prevents subsequent writebacks in the same file from targeting wrong lines after a recurrence insertion
- **Fixed double completion writeback** — Guard prevents writing `[x]` to already-completed tasks
- **Fixed delete+recreate cycle** — Removed mutable fields from `generateObsidianId()`; task IDs now use `filePath + title + tags + lineNumber` only
- **Fixed duplicate deletion during migration** — `relinkedRemindersIds` tracking prevents the same reminder from being deleted by stale mappings
- **Fixed recurring task ID collision** — Added `lineNumber` to ID components to disambiguate completed + uncompleted copies
- **Fixed backup errors during bulk sync** — File-exists check before backup to skip redundant backups within the same second
- **Fixed newline handling** — Changed all `components(separatedBy: .newlines)` to `components(separatedBy: "\n")`
- **Fixed settings tab visibility** — Increased window size and made General tab scrollable
- **Fixed folder exclusion matching** — Now matches by folder name, relative path, and path prefix
- **Fixed graceful file skip** — Unreadable files (broken symlinks, permissions) are skipped with a warning instead of failing the entire sync

### Technical Changes
- Sync state version bumped to v7 (stable IDs)
- v6 → v7 migration preserves existing mappings for graceful re-linking
- Score-based re-linking in `(.none, .some)` case with title + targetList + filePath matching
- Reconnect logic in `(.some, .none)` case checks existing reminders before recreating
- Step 5 deduplication builds title index of unmatched reminders to prevent duplicates after sync state reset
- Bundle identifier changed from `com.obsync.app` to `com.remindian.app`
- Application Support folder changed from `Obsync` to `Remindian`

---

## v2.0.0 (February 2026)

### New Features
- **Completion writeback** — Marking a task complete in Reminders surgically updates the Obsidian file (`- [x]` + `✅ YYYY-MM-DD`)
- **Recurrence handling** — Completing a recurring task creates a new uncompleted task with updated dates above the completed one
- **Metadata writeback** — Due date, start date, and priority changes from Reminders written back to Obsidian (atomic, surgical edits)
- **Dry run mode** — Full sync logic executes without making changes; reports what would change
- **Automatic file backups** — Every Obsidian file backed up before modification (`~/Library/Application Support/Remindian/backups/`)
- **Audit log** — Append-only log of every file modification with before/after content
- **Sync mutex** — NSLock prevents concurrent sync operations
- **Vault path validation** — Verifies vault exists and contains `.obsidian` directory
- **Line content verification** — Safety check before writing ensures file hasn't changed externally
- **Security-scoped bookmarks** — Vault access persists across app restarts in sandbox
- **Global hotkey** — Cmd+Shift+Option+S to trigger sync from any app (Carbon RegisterEventHotKey)
- **macOS notifications** — Sync errors and status updates via UNUserNotificationCenter
- **Sync history** — Last 200 sync operations with expandable detail view
- **Tag-based list mapping** — `#tag` → Reminders list with auto-capitalization fallback
- **Custom app icons** — Light, dark, and tinted variants with automatic switching
- **Force dark mode** — Toggle to force entire app UI to dark mode
- **Hide dock icon** — Run as menu bar-only app

### Safety: Disabled Dangerous Methods
The original `updateTask()`, `addTask()`, and `deleteTask()` methods in ObsidianService used `toObsidianLine()` to reconstruct task lines, which destroyed any metadata not explicitly modeled (recurrence markers `🔁`/`🔂`, custom metadata, non-standard formatting). All three are now marked `@available(*, deprecated)` and throw `ObsidianError.unsafeWriteDisabled`.

Replaced by surgical edit methods:
- `markTaskComplete()` — Only modifies `- [ ]` → `- [x]` and appends `✅ YYYY-MM-DD`
- `markTaskIncomplete()` — Reverses the above
- `updateTaskMetadata()` — Only replaces date digits or priority emoji, preserving all surrounding content

### Content-Hash Task IDs
Replaced line-number-based IDs (`filePath:lineNumber`) with content-hash IDs (`filePath + title + tags + lineNumber`). Tasks survive reordering, and the re-linking logic handles ID format migrations gracefully.

---

## v1.0.1 (February 2026)

- Fix: `.newerWins` compile error in SyncConfiguration (changed to `.obsidianWins`)
- Fix: Menu bar icon sizing using NSImage.SymbolConfiguration(pointSize: 14)
- Fix: "Open Settings" button using proper NSWindow approach instead of broken private API

---

## v1.0.0 (February 2026)

First public release. One-way sync from Obsidian Tasks to Apple Reminders.

- Scans Obsidian vault for tasks in Tasks plugin format
- Creates/updates/deletes Apple Reminders to match
- Priority emoji mapping (⏫/🔼/🔽 → Reminders priority levels)
- Due date sync (📅 → Reminders due date)
- Start date and scheduled date stored in Reminders notes
- Excluded folders configuration
- Auto-sync on configurable timer
- Menu bar app with sync status indicator

---

## Architecture

```
SwiftUI Layer: ContentView | SettingsView | MenuBarView | SyncHistoryView | AboutView
                    |
              SyncManager  (@MainActor ObservableObject singleton)
                    |
              SyncEngine   (core sync orchestrator, NSLock mutex)
               /        \
        TaskSource       TaskDestination
        (protocol)        (protocol)
          /    \            /       \
  Obsidian   TaskNotes  Reminders  Things3
  TasksSrc   Source     Destination Destination
     |          |          |           |
  ObsidianSvc  YAML     EventKit   AppleScript
  (vault I/O)  parser   (CRUD)     + URL scheme
       |
  FileBackupService | AuditLog
```

**Technology:** Swift 5, SwiftUI, EventKit, Carbon (hotkeys), UserNotifications, AppleScript (Things 3). No external dependencies.

## Data Storage

All persistent data under `~/Library/Application Support/Remindian/`:

| File | Purpose | Limit |
|------|---------|-------|
| `config.json` | User settings | ~2 KB |
| `sync_state.json` | Task ID mappings + hashes | Grows with task count |
| `sync_log.json` | Sync history | 200 entries |
| `audit.log` | File modification trail | 5 MB (rotates) |
| `backups/` | Pre-modification file copies | 50 per file, 7 days |
| `debug.log` | Debug output | Grows (manual cleanup) |

## Key Invariants

- **Never call `toObsidianLine()` in any write path.** All Obsidian writes must be surgical.
- **Always back up before writing.** Every code path modifying an Obsidian file calls `FileBackupService.backupFile()` first.
- **Always verify line content before writing.** The `lineContentMismatch` check is a critical safety net.
- **Bump `SyncState.stateVersion`** if you change the ID generation algorithm.
- **Completion detection must not be gated by `oChanged`.** The `completionDiffers` check always runs independently.

## Known Limitations

1. Recurrence rules are preserved in Obsidian files but not mapped to native EKRecurrenceRule in Reminders
2. Only "Obsidian Wins" conflict resolution is implemented
3. `toObsidianLine()` still exists as dead code (never called in safe paths)
4. Line number-based writeback can fail if file is modified between scan and write (safety check catches this)
5. Not notarized — requires right-click → Open on first launch
6. Tags used only for list mapping; not synced to Reminders tags (EventKit limitation)
