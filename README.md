# Remindian

<p align="center">
  <em>Remindian is free and open source. If it saves you time, consider buying me a coffee!</em>
</p>

<p align="center">
  <a href="https://www.buymeacoffee.com/santofer" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>
</p>

---

A native macOS menu-bar app that syncs your tasks between [Obsidian](https://obsidian.md), [Apple Reminders](https://support.apple.com/guide/reminders/welcome/mac), and [Things 3](https://culturedcode.com/things/).

Supports two task sources — the [Obsidian Tasks](https://publish.obsidian.md/tasks/Introduction) plugin format and the [TaskNotes](https://github.com/nicolo/obsidian-tasknotes) plugin — and two destinations — Apple Reminders and Things 3. Mix and match to build your ideal workflow.

**Your vault is the source of truth.** Tasks flow from Obsidian into your chosen destination. Completion status, due dates, start dates, priority, and tags can optionally be written back using surgical, metadata-preserving edits.

![Remindian main window](screenshots/main-window.png)

## Download

**[Download Remindian v3.7.0](https://github.com/Santofer/Remindian/releases/latest)** — Universal Binary (Apple Silicon + Intel), macOS 13.0+

> Since the app is not notarized, right-click the app and select **Open** on first launch to bypass Gatekeeper. Remindian includes a built-in auto-updater that checks for new versions on launch and every 24 hours.

## Features

### Task Sources
- **Obsidian Tasks** — Scans your vault for tasks in the Tasks plugin format (`- [ ] task 📅 2024-01-20 #tag`)
- **TaskNotes** — Reads TaskNotes plugin files (one `.md` file per task with YAML frontmatter). Supports CLI, Direct Files, and HTTP API integration modes

### Task Destinations
- **Apple Reminders** — Syncs to any Reminders list via EventKit
- **Things 3** — Syncs to Things 3 via AppleScript (read) and URL scheme (write)

### Sync Features
- **Two-way sync** — Tasks flow from your source to your destination; completions, due dates, start dates, priority, and tag changes sync back
- **Surgical file edits** — Never reconstructs task lines; preserves recurrence markers, tags, and all metadata
- **Recurrence support** — Completes recurring tasks and creates the next occurrence automatically
- **Tag-based list mapping** — `#work` or `+work` tasks go to your "Work" list, `#personal` to "Personal", etc.
- **Project/context list mapping** — Use the TaskNotes `project` or `context` field as the Reminders list instead of tags (supports wikilinks)
- **Configurable field mapping** — Remap YAML frontmatter field names to match your TaskNotes setup (e.g., `deadline` instead of `due`)
- **Custom status mapping** — Define which TaskNotes status values mean "completed" (e.g., `done`, `shipped`, `archived`)
- **Folder filtering** — Whitelist specific vault folders to scan, or exclude folders you don't want synced
- **Reminders list filtering** — Whitelist or blacklist specific Reminders lists for sync
- **GoodTask tag writeback** — Tag changes made in Reminders (e.g., via GoodTask's Kanban board) sync back to Obsidian `#tags`
- **Cross-file deduplication** — Detects duplicate tasks across files and syncs only one copy
- **New task writeback** — Tasks created in Reminders/Things can be written back to an Obsidian inbox file
- **Real-time sync** — File watcher triggers sync on vault changes (with self-change filtering to prevent loops)
- **Safety abort** — Sync aborts if task count drops dramatically (protects against vault unmounted or scan failures)
- **Dry run mode** — Preview what would change without making any actual modifications
- **Automatic backups** — Every Obsidian file is backed up before modification
- **Auto-updater** — Checks for new versions on launch and every 24 hours, with update notifications in the menu bar
- **Onboarding wizard** — Guided setup to choose your source, destination, vault path, and configuration
- **macOS native** — Built with SwiftUI, runs in the menu bar, Universal Binary, no external dependencies

## Quick Start

1. **Download** the DMG from the [latest release](https://github.com/Santofer/Remindian/releases/latest)
2. **Drag** Remindian to your Applications folder
3. **Right-click → Open** on first launch (required for unsigned apps)
4. **Follow** the onboarding wizard to select your vault, grant Reminders access, and configure folder filtering and tag mappings
5. Tasks will start syncing automatically

## Configuration

Open **Settings** from the menu bar icon to configure:

- **General** — Source & destination, vault path, sync interval, writeback toggles (completion, due date, start date, priority, tags), notifications, default list, launch at login, global hotkey
- **List Mappings** — Map Obsidian `#tags` or `+tags` to specific Reminders/Things lists
- **TaskNotes** *(shown when TaskNotes is selected)* — Integration mode (CLI/Files/HTTP), custom status mapping, field mapping (remap YAML field names), list/folder source (tags/project/context)
- **Advanced** — Folder whitelist/exclusions, Reminders list filtering, dry run mode, sync state reset, backup and audit log access

## How It Works

### With Obsidian Tasks (default)

Remindian scans your Obsidian vault for tasks in the [Tasks plugin](https://publish.obsidian.md/tasks/Introduction) format:

```markdown
- [ ] My task ⏫ 🛫 2024-01-15 📅 2024-01-20 #work
- [x] Completed task 📅 2024-01-10 ✅ 2024-01-09
- [ ] Recurring task 🔁 every week 📅 2024-03-01
```

### With TaskNotes

Reads one `.md` file per task with YAML frontmatter. Field names are fully configurable:

```markdown
---
title: My task
status: open
priority: high
due: 2024-01-20
scheduled: 2024-01-15
tags: [work]
project: "[[My Project]]"
---
# My task
Description of the task...
```

### Sync to Apple Reminders or Things 3

Each task is synced to your chosen destination with its due date, priority, and tags. When you complete a task, the completion is written back to Obsidian as a surgical edit — only the checkbox and completion date are modified, preserving all other metadata.

## Build from Source

```bash
git clone https://github.com/Santofer/Remindian.git
cd Remindian
open ObsidianRemindersSync.xcodeproj
```

**Requirements:** macOS 13.0+, Xcode 15.0+

The project builds a Universal Binary (Apple Silicon + Intel) by default.

## Transparency

AI (Claude) was used as a development tool during the creation of this app. The code has been reviewed, tested on real data, and the full source is open for anyone to audit. The app is sandboxed, creates automatic backups before every file modification, and includes a dry run mode for safe testing.

## License

[MIT License](LICENSE) — Made by **Santofer**.

See [CHANGELOG.md](CHANGELOG.md) for detailed version history and technical documentation.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.
