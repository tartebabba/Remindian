import Foundation
import AppKit

/// Things 3 destination using AppleScript (read) + URL scheme (write).
///
/// Architecture:
/// - READ: AppleScript via NSAppleScript for task properties (id, name, notes, due date, status, tags, project, area)
/// - CREATE: AppleScript-based creation for reliable task ID retrieval
/// - UPDATE: things:// URL scheme update command with auth-token
/// - DETECT CHANGES: Poll via AppleScript (no push mechanism in Things 3)
///
/// Limitations:
/// - Start date ("When") not readable via AppleScript (would need SQLite for that)
/// - Recurrence rules are read-only (only accessible via SQLite, not modifiable via any API)
/// - Auth token required for updates (user must provide from Things > Settings > General)
/// - No push/webhook — must poll for changes
/// - Checklist items not accessible via AppleScript
class Things3Destination: TaskDestination {
    let destinationName = "Things 3"

    /// The auth token from Things > Settings > General > Enable Things URLs > Manage
    var authToken: String = ""

    /// Clean tags for Things 3 — strip # prefix, preserve hierarchy as-is.
    /// Things 3 resolves hierarchical tags (e.g. "person/name") natively
    /// when they already exist in the tag tree. Sending parent tags separately
    /// would cause the task to be tagged with both "person" AND "person/name".
    private func cleanTagsForThings(_ tags: [String]) -> [String] {
        var cleaned: [String] = []
        var seen = Set<String>()
        for tag in tags {
            let stripped = tag.hasPrefix("#") ? String(tag.dropFirst()) : tag
            guard !stripped.isEmpty, seen.insert(stripped).inserted else { continue }
            cleaned.append(stripped)
        }
        return cleaned
    }

    // Cache for performance
    private var cachedLists: [String] = []
    private var lastListRefresh: Date?

    // MARK: - Authorization

    func requestAccess() async throws -> Bool {
        // Things 3 doesn't require explicit permission — we just need to check if it's installed
        guard isThings3Installed() else {
            throw Things3Error.notInstalled
        }

        // Test AppleScript access — use bundle ID for reliable resolution in sandbox
        let testScript = NSAppleScript(source: """
            tell application id "com.culturedcode.ThingsMac"
                return name
            end tell
        """)
        var error: NSDictionary?
        let result = testScript?.executeAndReturnError(&error)

        if error != nil {
            throw Things3Error.appleScriptAccessDenied
        }

        return result != nil
    }

    // MARK: - Fetching

    func fetchAllTasks() async throws -> [SyncTask] {
        var tasks: [SyncTask] = []

        // Fetch from active lists
        let activeLists = ["Today", "Inbox", "Anytime", "Upcoming", "Someday"]
        for listName in activeLists {
            let listTasks = try fetchTasksFromList(listName)
            tasks.append(contentsOf: listTasks)
        }

        // Fetch recently completed tasks from Logbook.
        // When a task is completed in Things 3, it moves to the Logbook.
        // Without this, the sync engine sees the task as "deleted" and recreates it.
        // We limit to the last 7 days to avoid fetching thousands of old completed tasks.
        let logbookTasks = try fetchRecentLogbookTasks(withinDays: 7)
        tasks.append(contentsOf: logbookTasks)
        debugLog("[Things3] Fetched \(logbookTasks.count) recently completed tasks from Logbook")

        return tasks
    }

    func getAvailableLists() async -> [String] {
        // Refresh cache every 60 seconds
        if let lastRefresh = lastListRefresh, Date().timeIntervalSince(lastRefresh) < 60 {
            return cachedLists
        }

        var lists = ["Inbox", "Today", "Anytime", "Upcoming", "Someday"]

        // Fetch projects and areas via AppleScript
        let script = NSAppleScript(source: """
            tell application id "com.culturedcode.ThingsMac"
                set projectNames to {}
                repeat with p in projects
                    set end of projectNames to name of p
                end repeat
                set areaNames to {}
                repeat with a in areas
                    set end of areaNames to name of a
                end repeat
                return {projectNames, areaNames}
            end tell
        """)

        var error: NSDictionary?
        if let result = script?.executeAndReturnError(&error) {
            // Parse the AppleScript result
            if result.numberOfItems >= 2 {
                // Projects
                if let projects = result.atIndex(1) {
                    for i in 1...max(1, projects.numberOfItems) {
                        if let name = projects.atIndex(i)?.stringValue {
                            lists.append("\u{1F4C1} \(name)")
                        }
                    }
                }
                // Areas
                if let areas = result.atIndex(2) {
                    for i in 1...max(1, areas.numberOfItems) {
                        if let name = areas.atIndex(i)?.stringValue {
                            lists.append("\u{1F4C2} \(name)")
                        }
                    }
                }
            }
        }

        cachedLists = lists
        lastListRefresh = Date()
        return lists
    }

    // MARK: - CRUD

    func createTask(from task: SyncTask, inList listName: String, config: SyncConfiguration) async throws -> String {
        // Use AppleScript to create task — more reliable than URL scheme for getting the task ID back
        let cleanList = listName
            .replacingOccurrences(of: "\u{1F4C1} ", with: "")
            .replacingOccurrences(of: "\u{1F4C2} ", with: "")

        let escapedTitle = task.title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedNotes = (task.notes ?? "").replacingOccurrences(of: "\"", with: "\\\"")

        // Build properties — due date is set via AppleScript date component construction
        // to avoid locale-dependent date literal parsing issues
        var properties = "name:\"\(escapedTitle)\""
        if !escapedNotes.isEmpty {
            properties += ", notes:\"\(escapedNotes)\""
        }
        if task.isCompleted {
            properties += ", status:completed"
        }

        // Build a locale-independent due date setter using AppleScript date components
        var dueDateScript = ""
        if let dueDate = task.dueDate {
            let cal = Calendar.current
            let y = cal.component(.year, from: dueDate)
            let m = cal.component(.month, from: dueDate)
            let d = cal.component(.day, from: dueDate)
            dueDateScript = """
                    set dueD to current date
                    set year of dueD to \(y)
                    set month of dueD to \(m)
                    set day of dueD to \(d)
                    set time of dueD to 0
                    set due date of newTodo to dueD
            """
        }

        // Build the creation script
        var scriptSource: String
        if listName.hasPrefix("\u{1F4C1} ") {
            // Create in a project
            let escapedProject = cleanList.replacingOccurrences(of: "\"", with: "\\\"")
            scriptSource = """
                tell application id "com.culturedcode.ThingsMac"
                    set newTodo to make new to do with properties {\(properties)}
                    move newTodo to project "\(escapedProject)"
                \(dueDateScript)
                    return id of newTodo
                end tell
            """
        } else {
            scriptSource = """
                tell application id "com.culturedcode.ThingsMac"
                    set newTodo to make new to do with properties {\(properties)}
                \(dueDateScript)
                    return id of newTodo
                end tell
            """
        }

        // Execute with retry — sandbox AppleScript can race against app initialization
        let (result, error) = executeAppleScriptWithRetry(source: scriptSource)
        guard let result = result,
              let taskId = result.stringValue, !taskId.isEmpty else {
            let message = (error?[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            throw Things3Error.appleScriptError("Failed to create task: \(message)")
        }

        // Set tags via URL scheme if auth token is available (AppleScript can't set tags on creation)
        if !task.tags.isEmpty && !authToken.isEmpty {
            let tagNames = cleanTagsForThings(task.tags)
            try updateTaskViaURLScheme(params: [
                "id": taskId,
                "auth-token": authToken,
                "tags": tagNames.joined(separator: ",")
            ])
        }

        debugLog("[Things3] Created task \"\(task.title)\" with id=\(taskId)")
        return taskId
    }

    func updateTask(withId id: String, from task: SyncTask, config: SyncConfiguration) async throws {
        guard !authToken.isEmpty else {
            // Don't throw — allow sync to continue for creation-only workflows.
            // Updates require the auth token, but new tasks are created via AppleScript.
            debugLog("[Things3] Skipping update for \"\(task.title)\" — no auth token configured. Go to Things > Settings > General > Enable Things URLs to get your token.")
            return
        }

        var params: [String: String] = [
            "id": id,
            "auth-token": authToken
        ]

        params["title"] = task.title

        if let dueDate = task.dueDate {
            params["deadline"] = formatDate(dueDate)
        } else {
            params["deadline"] = "" // Clear deadline
        }

        if task.isCompleted {
            params["completed"] = "true"
        }

        if let notes = task.notes {
            params["notes"] = notes
        }

        // Sync tags (#32 — tag changes were not being sent to Things 3)
        // Clean tags for Things 3 — strip # prefix, preserve hierarchy (#45)
        if !task.tags.isEmpty {
            let tagNames = cleanTagsForThings(task.tags)
            params["tags"] = tagNames.joined(separator: ",")
        }

        var components = URLComponents()
        components.scheme = "things"
        components.host = ""
        components.path = "/update"
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else {
            throw Things3Error.invalidURL
        }

        let success = NSWorkspace.shared.open(url)
        if !success {
            throw Things3Error.urlSchemeNotHandled
        }
    }

    func moveTask(withId id: String, toList listName: String) async throws {
        guard !authToken.isEmpty else {
            debugLog("[Things3] Skipping move — no auth token configured")
            return
        }

        let cleanList = listName
            .replacingOccurrences(of: "\u{1F4C1} ", with: "")
            .replacingOccurrences(of: "\u{1F4C2} ", with: "")

        var params: [String: String] = [
            "id": id,
            "auth-token": authToken,
            "list": cleanList
        ]

        var components = URLComponents()
        components.scheme = "things"
        components.host = ""
        components.path = "/update"
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else {
            throw Things3Error.invalidURL
        }

        let success = NSWorkspace.shared.open(url)
        if !success {
            throw Things3Error.urlSchemeNotHandled
        }
    }

    func deleteTask(withId id: String) async throws {
        // Things 3 URL scheme doesn't support deletion.
        // Use AppleScript to move to Trash instead.
        let scriptSource = """
            tell application id "com.culturedcode.ThingsMac"
                set theTodo to to do id "\(id)"
                delete theTodo
            end tell
        """

        let (_, error) = executeAppleScriptWithRetry(source: scriptSource)

        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw Things3Error.appleScriptError(message)
        }
    }

    func refresh() {
        cachedLists = []
        lastListRefresh = nil
    }

    // MARK: - AppleScript Helpers

    /// Execute an AppleScript with one retry on failure.
    /// If the first attempt fails (e.g., app not initialized), we retry once with a
    /// `launch` preamble to ensure Things 3 is running.
    private func executeAppleScriptWithRetry(source: String) -> (NSAppleEventDescriptor?, NSDictionary?) {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)

        if let error = error {
            let message = error[NSAppleScript.errorMessage] as? String ?? ""
            debugLog("[Things3] AppleScript failed (attempt 1): \(message)")

            // Retry with an explicit launch + short delay in case Things wasn't ready
            Thread.sleep(forTimeInterval: 0.5)
            let retrySource = source.replacingOccurrences(
                of: "tell application id \"com.culturedcode.ThingsMac\"",
                with: "tell application id \"com.culturedcode.ThingsMac\"\n                launch\n                delay 0.3"
            )
            debugLog("[Things3] Retrying AppleScript with launch...")

            var retryError: NSDictionary?
            let retryScript = NSAppleScript(source: retrySource)
            let retryResult = retryScript?.executeAndReturnError(&retryError)

            if let retryError = retryError {
                let retryMessage = retryError[NSAppleScript.errorMessage] as? String ?? ""
                debugLog("[Things3] AppleScript failed (attempt 2): \(retryMessage)")
                return (nil, retryError)
            }

            debugLog("[Things3] AppleScript succeeded on retry")
            return (retryResult, nil)
        }

        return (result, nil)
    }

    /// Send an update to Things 3 via URL scheme (locale-independent).
    private func updateTaskViaURLScheme(params: [String: String]) throws {
        var components = URLComponents()
        components.scheme = "things"
        components.host = ""
        components.path = "/update"
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else { return }
        let success = NSWorkspace.shared.open(url)
        if !success {
            debugLog("[Things3] URL scheme update failed for task \(params["id"] ?? "?")")
        }
    }

    /// Fetch recently completed tasks from the Things 3 Logbook.
    /// Uses AppleScript date comparison to limit results to `withinDays` days,
    /// avoiding the performance hit of fetching thousands of old completed tasks.
    private func fetchRecentLogbookTasks(withinDays days: Int) throws -> [SyncTask] {
        // AppleScript: iterate Logbook tasks, skip those completed more than N days ago.
        // Things 3 Logbook is sorted by completion date (newest first), so we stop
        // early once we hit a task older than the cutoff.
        let script = NSAppleScript(source: """
            tell application id "com.culturedcode.ThingsMac"
                set cutoff to (current date) - \(days) * days
                set todoList to {}
                repeat with toDo in to dos of list "Logbook"
                    set todoCompletionDate to ""
                    try
                        set todoCompletionDate to completion date of toDo
                    end try
                    if todoCompletionDate is not "" then
                        if todoCompletionDate < cutoff then exit repeat
                    end if

                    set todoId to id of toDo
                    set todoName to name of toDo
                    set todoNotes to notes of toDo
                    set todoStatus to status of toDo
                    set todoDueDate to ""
                    try
                        set todoDueDate to due date of toDo as string
                    end try
                    set todoCompletionDateStr to ""
                    try
                        set todoCompletionDateStr to completion date of toDo as string
                    end try
                    set todoTagNames to tag names of toDo
                    set todoProject to ""
                    try
                        set todoProject to name of project of toDo
                    end try
                    set todoArea to ""
                    try
                        set todoArea to name of area of toDo
                    end try

                    set todoData to todoId & "|||" & todoName & "|||" & todoNotes & "|||" & (todoStatus as string) & "|||" & todoDueDate & "|||" & todoCompletionDateStr & "|||" & todoTagNames & "|||" & todoProject & "|||" & todoArea
                    set end of todoList to todoData
                end repeat
                set AppleScript's text item delimiters to "~~~"
                return todoList as string
            end tell
        """)

        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error),
              let resultString = result.stringValue else {
            if let error = error {
                let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                debugLog("[Things3] AppleScript error fetching Logbook: \(message)")
            }
            return []
        }

        guard !resultString.isEmpty else { return [] }

        var tasks: [SyncTask] = []
        let todoStrings = resultString.components(separatedBy: "~~~")

        for todoStr in todoStrings {
            let parts = todoStr.components(separatedBy: "|||")
            guard parts.count >= 4 else { continue }

            let id = parts[0]
            let name = parts[1]
            let notes = parts.count > 2 ? parts[2] : ""
            let statusStr = parts.count > 3 ? parts[3] : ""
            let dueDateStr = parts.count > 4 ? parts[4] : ""
            let completionDateStr = parts.count > 5 ? parts[5] : ""
            let tagNames = parts.count > 6 ? parts[6] : ""
            let project = parts.count > 7 ? parts[7] : ""
            let area = parts.count > 8 ? parts[8] : ""

            let isCompleted = statusStr.contains("completed")
            let dueDate = parseAppleScriptDate(dueDateStr)
            let completionDate = parseAppleScriptDate(completionDateStr)

            let tags = tagNames.isEmpty ? [] : tagNames.components(separatedBy: ", ").map { "#\($0)" }
            let targetList = !project.isEmpty ? project : (!area.isEmpty ? area : "Logbook")

            let task = SyncTask(
                title: name,
                isCompleted: isCompleted,
                priority: .none,
                dueDate: dueDate,
                completedDate: completionDate,
                tags: tags,
                targetList: targetList,
                notes: notes.isEmpty ? nil : notes,
                remindersId: id,
                lastModified: completionDate ?? Date()
            )
            tasks.append(task)
        }

        return tasks
    }

    /// Fetch tasks from a specific Things 3 list via AppleScript.
    private func fetchTasksFromList(_ listName: String) throws -> [SyncTask] {
        let script = NSAppleScript(source: """
            tell application id "com.culturedcode.ThingsMac"
                set todoList to {}
                repeat with toDo in to dos of list "\(listName)"
                    set todoId to id of toDo
                    set todoName to name of toDo
                    set todoNotes to notes of toDo
                    set todoStatus to status of toDo
                    set todoDueDate to ""
                    try
                        set todoDueDate to due date of toDo as string
                    end try
                    set todoCompletionDate to ""
                    try
                        set todoCompletionDate to completion date of toDo as string
                    end try
                    set todoTagNames to tag names of toDo
                    set todoProject to ""
                    try
                        set todoProject to name of project of toDo
                    end try
                    set todoArea to ""
                    try
                        set todoArea to name of area of toDo
                    end try

                    set todoData to todoId & "|||" & todoName & "|||" & todoNotes & "|||" & (todoStatus as string) & "|||" & todoDueDate & "|||" & todoCompletionDate & "|||" & todoTagNames & "|||" & todoProject & "|||" & todoArea
                    set end of todoList to todoData
                end repeat
                set AppleScript's text item delimiters to "~~~"
                return todoList as string
            end tell
        """)

        var error: NSDictionary?
        guard let result = script?.executeAndReturnError(&error),
              let resultString = result.stringValue else {
            if let error = error {
                let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                debugLog("[Things3] AppleScript error fetching \(listName): \(message)")
            }
            return []
        }

        guard !resultString.isEmpty else { return [] }

        var tasks: [SyncTask] = []
        let todoStrings = resultString.components(separatedBy: "~~~")

        for todoStr in todoStrings {
            let parts = todoStr.components(separatedBy: "|||")
            guard parts.count >= 4 else { continue }

            let id = parts[0]
            let name = parts[1]
            let notes = parts.count > 2 ? parts[2] : ""
            let statusStr = parts.count > 3 ? parts[3] : ""
            let dueDateStr = parts.count > 4 ? parts[4] : ""
            let completionDateStr = parts.count > 5 ? parts[5] : ""
            let tagNames = parts.count > 6 ? parts[6] : ""
            let project = parts.count > 7 ? parts[7] : ""
            let area = parts.count > 8 ? parts[8] : ""

            let isCompleted = statusStr.contains("completed")
            let dueDate = parseAppleScriptDate(dueDateStr)
            let completionDate = parseAppleScriptDate(completionDateStr)

            let tags = tagNames.isEmpty ? [] : tagNames.components(separatedBy: ", ").map { "#\($0)" }
            let targetList = !project.isEmpty ? project : (!area.isEmpty ? area : listName)

            let task = SyncTask(
                title: name,
                isCompleted: isCompleted,
                priority: .none, // Things 3 doesn't expose priority via AppleScript
                dueDate: dueDate,
                completedDate: completionDate,
                tags: tags,
                targetList: targetList,
                notes: notes.isEmpty ? nil : notes,
                remindersId: id,
                lastModified: completionDate ?? Date()
            )
            tasks.append(task)
        }

        return tasks
    }

    private func isThings3Installed() -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.culturedcode.ThingsMac") != nil
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Format date for AppleScript date literal.
    private func formatAppleScriptDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: date)
    }

    private func parseAppleScriptDate(_ dateStr: String) -> Date? {
        guard !dateStr.isEmpty else { return nil }
        // AppleScript dates come in locale-dependent format
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if let date = formatter.date(from: dateStr) { return date }

        // Try ISO format
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        return isoFormatter.date(from: dateStr)
    }
}

// MARK: - Errors

enum Things3Error: LocalizedError {
    case notInstalled
    case appleScriptAccessDenied
    case appleScriptError(String)
    case authTokenRequired
    case invalidURL
    case taskNotFound(String)
    case urlSchemeNotHandled

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Things 3 is not installed. Please install Things 3 from the Mac App Store."
        case .appleScriptAccessDenied:
            return "Cannot access Things 3 via AppleScript. Please grant access in System Settings > Privacy & Security > Automation."
        case .appleScriptError(let message):
            return "Things 3 AppleScript error: \(message)"
        case .authTokenRequired:
            return "Things 3 auth token required for updates. Go to Things > Settings > General > Enable Things URLs to get your token."
        case .invalidURL:
            return "Failed to build Things URL"
        case .taskNotFound(let title):
            return "Could not find Things task: \(title)"
        case .urlSchemeNotHandled:
            return "Things 3 URL scheme failed. Make sure Things 3 is installed and the things:// URL scheme is registered."
        }
    }
}
