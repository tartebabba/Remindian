# Changelog

All notable changes to Remindian (formerly Obsync) are documented here.

---

## v5.4.0 (March 2026)

### Unified Single-Window Experience
- **Settings embedded in main window** — No more separate Settings window. General, Mappings, TaskNotes, and Advanced settings are now tabs alongside Conflicts and History in the main detail pane
- **Liquid Glass tabs** — All tabs (settings + activity) share the same tab bar with Liquid Glass treatment on macOS Tahoe
- **Fewer windows** — The app is now fully contained in a single window with sidebar + tabbed detail
- **Menu bar "Settings..."** now opens the main window directly

---

## v5.3.0 (March 2026)

### Native macOS Settings Window
- **Toolbar-style icon tabs** — Settings now opens the native macOS Settings scene, giving the classic Preferences look with icons + labels in the toolbar (like Mail.app, Xcode)
- **Brand icons** — Todoist, Things 3, TickTick, Asana, and Linear show their real logos in the destination picker (sourced from SimpleIcons, rendered as template images)
- **Grouped form style** — All settings sections use `.formStyle(.grouped)` for modern rounded-card sections (like System Settings)
- **Better tab icons** — "Mappings" tab uses swap arrows, "Advanced" uses horizontal sliders instead of wrench

---

## v5.2.0 (March 2026)

### Design Overhaul — Liquid Glass (macOS Tahoe)
- **NavigationSplitView dashboard** — On macOS 26+, the main window uses a native sidebar/detail split with automatic floating glass sidebar, replacing the legacy HSplitView
- **Glass toolbar** — Sync button and status move into the native toolbar, which gets automatic Liquid Glass treatment on Tahoe. Traffic lights (close/minimize/maximize) integrate naturally into the content area
- **Transparent titlebar** — All programmatically created windows (main, settings, about) use `titlebarAppearsTransparent` + `fullSizeContentView` on macOS 26+ for seamless glass
- **Glass sidebar sections** — Sync Status and Configuration panels use `.glassEffect(.regular)` directly on macOS 26+ instead of wrapping the entire view in a glass blob
- **Full backward compatibility** — macOS 13-15 users see the exact same UI as before. All glass is conditionally applied with `@available(macOS 26, *)`

### UI Improvements (all macOS versions)
- **Settings window size** — Default 750×700, minimum 650×550 (up from 550×580)
- **Settings scroll fix** — List Mappings tab now scrollable; no more content clipping
- **Flexible field widths** — Mapping input fields flex with window resize

---

## v5.1.0 (March 2026)

### UI Improvements
- **Fixed Settings layout** — List Mappings tab now scrolls properly; content no longer crops or overflows outside the window
- **Larger Settings window** — Default size increased to 750x700 with proper minimum size constraints
- **Flexible field widths** — Mapping input fields now flex with window resizing instead of using fixed widths
- **Liquid Glass (macOS Tahoe)** — Dashboard panels and Settings adopt Apple's Liquid Glass design on macOS 26+. Falls back gracefully on older macOS versions

---

## v5.0.0 (March 2026)

**First stable GA release.** Remindian is no longer beta.

### New Features
- **Tag exclusion (#47)** — Exclude tasks with specific tags from syncing (e.g., "Routine"). Configure in Settings > Exclude Tags
- **TaskNotes subdirectory scanning (#48)** — TaskNotes now recursively scans all subdirectories within the configured folder, so you can organize task notes by project
- **Homebrew tap (#35)** — Install via `brew tap Santofer/remindian && brew install --cask remindian`

### Performance
- **Faster Things 3 sync** — Tags are now set directly in the AppleScript batch call instead of separate URL scheme operations, eliminating per-task throttle delays

### Bug Fixes
- **Fixed crash-on-launch (#38)** — Eliminated all force unwraps across the entire codebase. Malformed URLs, corrupted data, or unexpected nil values are now handled gracefully instead of crashing
- **Version display** — About section now correctly shows the running version

---

## v4.3.1 (March 2026)

### New Features
- **Obsidian link in Things 3** — Tasks synced to Things 3 now include a clickable `obsidian://` link in the notes field, just like Apple Reminders. Click it to jump straight to the source file in Obsidian
- **Task Notes body synced** — The markdown body content of TaskNotes files (below the YAML frontmatter) is now included as the task notes in the destination

### Bug Fixes
- **Fixed MTN exit 126 in sandbox** — The macOS sandbox blocks CLI execution even with `chmod +x`. The app now automatically falls back to "Direct Files" mode when mtn CLI fails, which reads/writes task files directly without needing the mtn binary
- **10x faster Things 3 sync** — Task creation now uses batch AppleScript (up to 20 tasks per call) instead of one-at-a-time. URL scheme throttle reduced from 150ms to 50ms. 100 tasks should now sync in under a minute instead of 7-12 minutes
- **Fixed version display** — Xcode project build settings (`MARKETING_VERSION`) now stay in sync with `Info.plist`

---

## v4.3.0 (March 2026)

### Bug Fixes
- **Fixed Things 3 hierarchical tags (again)** — Tags like `person/name` now send only the leaf name (`name`) via URL scheme. Things 3 resolves the hierarchy natively; sending the full path caused percent-encoding (`person%2Fname`) which didn't match existing tags
- **Improved Things 3 sync speed** — Added 150ms throttle between URL scheme calls to prevent overwhelming Things 3 with rapid-fire updates. Reduced retry delay from 0.5s to 0.3s
- **Fixed first-launch auto-sync** — Onboarding no longer triggers an immediate sync. Users with large vaults were getting hundreds of tasks created in their destination on first launch before reviewing settings
- **Better MTN error messages** — Exit code 126 ("not executable") now shows a clear fix: `chmod +x /path/to/mtn`. Also pre-checks binary permissions before attempting to run
- **Updated About view** — Release date now shows March 2026

---

## v4.2.2 (March 2026)

### Bug Fixes
- **Fixed Things 3 hierarchical tags** — Tags like `person/name` were being expanded to both `person` and `person/name`, causing tasks to get tagged with the parent tag as a standalone tag. Now sends only the full tag path and lets Things 3 resolve the hierarchy natively

---

## v4.2.1 (March 2026)

### Bug Fixes
- **Fixed crash on launch** — Eliminated 6 force-unwrap (`first!`) calls on `applicationSupportDirectory` that could crash the app immediately on startup if the directory wasn't available. All persistence code now uses a safe `remindianAppSupportDir()` helper that returns nil instead of crashing
- **Hardened startup sequence** — Each initialization step in `AppDelegate` is now isolated with diagnostic logging, so one subsystem failure doesn't take down the entire app
- **Note for unsigned app users** — If macOS blocks the app with "damaged" or "quit unexpectedly", run `xattr -cr /Applications/Remindian.app` in Terminal before opening

---

## v4.2.0 (March 2026)

### New Features
- **Folder-to-list mapping** (#40) — Map entire vault folders to specific destination lists. All tasks in any file within the mapped folder (and subfolders) sync to the specified list. More specific folders take priority over broader ones (e.g., `Projects/Work/` beats `Projects/`). Configure in Settings > List Mappings
- **Dataview inline field support** (#41) — Parse `[key::value]` and `(key::value)` metadata from task lines. Recognized fields: `due`, `start`, `scheduled`, `completed`, `priority`, `tags`, `project`, `list`. Emoji-based metadata takes precedence; dataview fields fill in any gaps. Enable in Settings > Advanced > "Parse dataview inline fields"
- **Asana destination** (#42) — Sync tasks to Asana via the REST API v1. Tasks map to Asana tasks, lists map to Asana projects. Supports due dates, start dates, completion status, notes. Auth via Personal Access Token
- **Linear destination** (#43) — Sync tasks to Linear via the GraphQL API. Tasks map to Linear issues, lists map to Linear teams. Supports due dates, priority mapping (Urgent/High/Medium/Low), labels as tags, completion via workflow states. Auth via Personal API Key
- **Calendar Feed destination** (#44) — Generate a subscribable .ics (iCalendar) file from your tasks. Tasks become RFC 5545 VTODO entries with due dates, priorities, and completion status. Subscribe from Apple Calendar, Google Calendar, or any CalDAV client

### Bug Fixes
- **Fixed Todoist sync** (#39) — Todoist REST v2 API is 410 Gone. Switched to API v1 with proper paginated response handling (`{ "results": [...], "next_cursor": "..." }`) and fixed field name mismatch (`checked` instead of `isCompleted`)
- **Fixed destination switching** — `hasRemindersAccess` was blocking all non-Reminders destinations. Renamed to `hasDestinationAccess` with per-destination permission UI and automatic re-request on destination switch
- **Fixed Things 3 completion writeback** — Completing a task in Things 3 moves it to the Logbook, which wasn't being fetched. The sync engine saw the task as "deleted" and recreated it. Now fetches recently completed tasks (last 7 days) from the Logbook and correctly writes completion back to Obsidian. Also skips redundant destination updates when completion flows from Things→Obsidian
- **Fixed list filtering for completed tasks** — Already-mapped destination tasks are no longer filtered out by the allowed/excluded lists whitelist. This ensures completion writeback works even when tasks move to a different list (e.g. Things 3 Logbook)
- **Fixed cross-file dedup collapsing unique tasks** (#46) — Tasks with identical titles in different files (e.g. "Review imported meeting notes" in multiple meeting note files) were incorrectly collapsed into a single reminder. Dedup now only removes duplicates when one copy is in Inbox.md (writeback artifact)
- **Fixed MTN sandbox permission error** (#45) — `mtn` CLI invocation via `/bin/sh -l` failed with "Operation not permitted" because login shell tries to source `/etc/profile` which is blocked by the macOS sandbox. Removed `-l` flag; PATH is set explicitly
- **Fixed Things 3 auth token blocking sync** (#45) — Missing or invalid auth token was throwing errors that blocked all sync operations. Now gracefully skips update/move operations when no token is configured, allowing creation-only workflows
- **Improved Things 3 sync speed** (#45) — Removed unnecessary `launch` + `delay 0.5` from every AppleScript execution (saves ~0.5s per task operation). Reduced retry delay from 1.5s to 0.5s. Retry now adds `launch` only when needed
- **Added hierarchical tag support for Things 3** (#45) — Tags like `#person/name` now auto-expand to include parent tags (`person`, `person/name`) so Things 3 creates the correct tag hierarchy
- **Increased Settings panel minimum size** (#45) — Enlarged from 550×500 to 650×600 to prevent content truncation

### Technical Changes
- New `SyncConfiguration.FolderMapping` struct with `folderPath` and `remindersList` fields
- `resolveTargetList()` now checks folder mappings between file mappings and auto-capitalize (most specific folder wins)
- New `SyncTask.parseDataviewFields(from:into:)` static method parses both bracket and parenthetical syntax
- `ObsidianTasksSource.scanTasks()` applies dataview parsing when `enableDataviewFormat` is enabled
- Mapping priority: explicit tag > file path > folder path > auto-capitalize tag > default list
- New `AsanaDestination` with REST API, workspace/project resolution, paginated task fetching, rate limit retry
- New `LinearDestination` with GraphQL API, team/workflow state resolution, priority mapping, paginated issue fetching
- New `CalendarFeedDestination` with RFC 5545 .ics generation, VTODO entries, ICS parsing for round-trip
- `TaskDestinationType` enum expanded: `.asana`, `.linear`, `.calendarFeed` with display names and config properties
- `PermissionRequestView`, `OnboardingView`, `SettingsView` updated for all 7 destination types
- 16 new tests (65 total): folder mapping resolution, specificity, encoding, dataview field parsing, priority preservation, cross-file dedup

---

## v4.1.0-beta (March 2026)

### New Features
- **File-to-list mapping** (#37) — Map specific Obsidian files to specific destination lists. All tasks in a mapped file (e.g., `Projects/Work.md`) sync to the specified list without needing to tag each task individually. Configure in Settings > List Mappings

### Bug Fixes
- **Fixed Things 3 "application not running" error** — AppleScript blocks now use `tell application id "com.culturedcode.ThingsMac"` (bundle identifier) instead of `tell application "Things3"` (display name), which resolves reliably in sandboxed macOS apps. Write operations (`createTask`, `deleteTask`) also include an explicit `launch` command to ensure Things 3 is active before sending commands. This fixes the issue where dry run worked but actual sync failed with "application not running"

### Technical Changes
- New `SyncConfiguration.FileMapping` struct with `filePath` and `remindersList` fields
- New `resolveTargetList(tag:filePath:)` method encapsulates the full resolution chain: explicit tag mapping > file path mapping > auto-capitalize tag > default list
- `SyncEngine` uses `resolveTargetList` at all 6 list routing call sites
- 7 new tests covering file mapping resolution priority, encode/decode, and backward compatibility (49 total)

---

## v4.0.0-beta (March 2026)

### New Features
- **Todoist destination** — Sync tasks to Todoist via the REST API v1. Supports personal API token auth, project mapping, priority sync (high/medium/low), label/tag sync, and due date with optional time
- **TickTick destination** — Sync tasks to TickTick via the Open API v1. Uses OAuth 2.0 with automatic token refresh. Supports project mapping, priority sync, and due dates. Note: TickTick's Open API does not support tags/labels
- **Custom URL scheme** — `remindian://` URL scheme for OAuth callbacks (TickTick authorization flow)

### Technical Changes
- **Protocol evolution** — All `TaskDestination` CRUD methods (`createTask`, `updateTask`, `moveTask`, `deleteTask`, `getAvailableLists`) are now `async throws`, enabling REST API destinations alongside existing local destinations
- New `TodoistDestination` with full CRUD, rate limit retry (429 + Retry-After), priority/label/date mapping
- New `TickTickDestination` with OAuth 2.0 token management, project iteration (no global task endpoint), project-scoped operations
- New `OAuthCallbackHandler` singleton for `remindian://` URL scheme routing
- `SyncManager` gains `connectTickTick()`, `handleTickTickOAuthCode()`, `disconnectTickTick()` for TickTick OAuth lifecycle
- `SyncConfiguration` gains `.todoist` and `.tickTick` destination types with associated token/credential storage
- `SyncEngine.resolveConflict()` now `async throws` to match protocol changes
- Settings UI updated with Todoist API token field and TickTick connect/disconnect button

---

## v3.7.0 (March 2026)

### Bug Fixes
- **Fixed Things 3 duplicate syncing** — Task creation switched from URL scheme to AppleScript, which returns the task ID directly. Eliminates the unreliable title-based search that only checked Inbox/Today, causing duplicates when Things 3 routed tasks to projects or other lists
- **Fixed Things 3 "no app to open URL scheme" errors** — `NSWorkspace.shared.open(url)` return value is now checked and throws a clear error instead of silently failing
- **Fixed Things 3 tag changes not syncing** (#32) — `updateTask()` was not including tags in the URL scheme parameters, so tag/project changes from Obsidian never propagated to Things 3
- **Fixed Settings UX for default list vs project routing** (#33) — Added contextual help text explaining how the default list interacts with TaskNotes project/context routing. The default list is now clearly labeled as a fallback

### New Features
- **Obsidian Tasks global filter** (#36) — New "Global filter" field in Advanced settings. Only syncs tasks whose line contains the specified text (e.g., `#task`), matching the Obsidian Tasks plugin's global filter setting

### Technical Changes
- `Things3Destination.createTask()` rewritten to use AppleScript instead of URL scheme for reliable task ID retrieval
- `Things3Destination.updateTask()` now sends tags in URL scheme params
- New `Things3Error.urlSchemeNotHandled` error case for URL scheme failures
- New `updateTaskTags(withId:tags:)` helper for setting tags after AppleScript creation
- New `formatAppleScriptDate()` helper for AppleScript date literals
- Removed `findTaskIdByTitle()` — no longer needed with AppleScript-based creation
- `SyncConfiguration.globalFilter` property added with full encode/decode support
- `ObsidianTasksSource.scanTasks()` applies global filter post-scan

---

## v3.6.0 (February 2026)

### Bug Fixes
- **Fixed crash on launch** — `@ObservedObject` in MenuBarView caused the updater to be recreated on every SwiftUI redraw, crashing the app after a few seconds. Changed to `@StateObject` for stable ownership
- **Fixed tag writeback not forwarding tags** — `ObsidianTasksSource.updateTaskMetadata()` was not passing `newTags` to the underlying `ObsidianService`, silently dropping tag changes
- **Fixed TaskNotes projects not creating Reminders folders** — YAML values with quotes (e.g., `project: "My Project"`) kept literal quote characters, causing list creation to fail. Now strips YAML quotes during frontmatter parsing (#28)
- **Fixed auto-sync on first launch** — App was triggering a sync immediately after Reminders permission was granted, before the user completed onboarding. Now waits until onboarding is complete (#25)
- **Fixed Reset Sync State inconsistency** — The dashboard and Advanced settings had different Reset buttons with different behaviors. Both now use a confirmation dialog and perform a comprehensive reset: clears sync state mappings, sync log, debug log, and resets first-sync flag (#29, #30)

### New Features
- **Sync stop/cancel button** — Cancel a running sync at any time from the main window header or menu bar dropdown. Uses cooperative cancellation with checks at key sync points (#26)
- **Icon tooltips** — All sync status icons (created, updated, deleted, completions, metadata) now show descriptive tooltips on hover. Menu bar status dot also explains its color meaning (#31)
- **Redesigned Settings** — Split the cluttered Advanced tab into separate tabs: General, List Mappings, TaskNotes (conditional), and Advanced. TaskNotes configuration gets its own dedicated tab with organized sections for Integration, Status Mapping, Field Mapping, and List/Folder Source (#24)

### Technical Changes
- `MenuBarView` uses `@StateObject` instead of `@ObservedObject` for `UpdaterService.shared`
- `SyncManager` gains `currentSyncTask` tracking and `cancelSync()` method
- `SyncEngine` gains `_cancellationRequested` flag with `NSLock`-based thread safety and `requestCancellation()`/`isCancelled` API
- `SyncError.syncCancelled` added for clean cancellation reporting
- `TaskNotesSource.parseTaskNotesFile()` strips YAML single/double quotes from frontmatter values
- `SettingsView` split into `GeneralSettingsView`, `ListMappingsSettingsView`, `TaskNotesSettingsView`, `AdvancedSettingsView`
- New `FieldMappingRow` helper view for individual field mapping display
- Reset confirmation dialog shared between dashboard and advanced settings
- `.help()` tooltips added to all `StatBadge` and menu bar sync result icons

---

## v3.5.1 (February 2026)

### Bug Fixes
- **Auto-update now works on app launch** — The update checker was only initialized when the About window was opened. It now starts automatically when the app launches and checks every 24 hours (#23)
- **Update download works in sandboxed builds** — Replaced `Process()`-based DMG mount/install (blocked by sandbox) with browser-based download. Clicking "Download Update" opens the DMG in your browser for drag-install
- **Update notification in menu bar** — When an update is available, it now shows directly in the menu bar dropdown (no need to open the About view)
- **Fixed deprecated notification API** — Replaced removed `NSUserNotification` with modern `UNUserNotificationCenter` via `NotificationService`

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
