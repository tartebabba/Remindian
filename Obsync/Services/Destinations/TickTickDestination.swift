import Foundation
import AppKit

/// TickTick destination using the Open API v1.
///
/// Architecture:
/// - AUTH: OAuth 2.0 (Authorization Code flow via remindian:// URL scheme callback)
/// - READ: GET /project (list projects) + GET /project/{id}/data (tasks per project)
/// - CREATE: POST /task
/// - UPDATE: POST /task/{id}
/// - COMPLETE: POST /project/{pid}/task/{tid}/complete
/// - DELETE: DELETE /project/{pid}/task/{tid}
///
/// Limitations:
/// - No global "list all tasks" endpoint — must iterate all projects
/// - No tag/label support in the Open API
/// - OAuth required (no simple API token)
///
/// API docs: https://developer.ticktick.com/
class TickTickDestination: TaskDestination {
    let destinationName = "TickTick"

    var accessToken: String = ""
    var refreshToken: String = ""
    var tokenExpiry: Date?

    private let baseURL = "https://api.ticktick.com/open/v1"
    private let session = URLSession.shared

    // TickTick OAuth credentials — register at developer.ticktick.com
    static let clientId = ""  // Set after registering app
    static let clientSecret = ""  // Set after registering app
    static let redirectURI = "remindian://oauth/ticktick"

    // Cache
    private var cachedProjects: [TickTickProject] = []
    private var lastProjectRefresh: Date?

    // MARK: - Authorization

    func requestAccess() async throws -> Bool {
        guard !accessToken.isEmpty else {
            throw TickTickError.notConnected
        }
        try await ensureValidToken()
        // Verify by fetching projects
        let (_, response) = try await makeRequest(method: "GET", path: "/project")
        return response.statusCode == 200
    }

    // MARK: - Fetching

    func fetchAllTasks() async throws -> [SyncTask] {
        try await ensureValidToken()
        let projects = try await fetchProjects()
        var allTasks: [SyncTask] = []

        for project in projects {
            let tasks = try await fetchTasksInProject(project)
            allTasks.append(contentsOf: tasks)
        }

        return allTasks
    }

    func getAvailableLists() async -> [String] {
        if let lastRefresh = lastProjectRefresh, Date().timeIntervalSince(lastRefresh) < 60 {
            return cachedProjects.map { $0.name }
        }
        do {
            try await ensureValidToken()
            let projects = try await fetchProjects()
            cachedProjects = projects
            lastProjectRefresh = Date()
            return projects.map { $0.name }
        } catch {
            debugLog("[TickTick] Failed to fetch projects: \(error)")
            return cachedProjects.map { $0.name }
        }
    }

    // MARK: - CRUD

    func createTask(from task: SyncTask, inList listName: String, config: SyncConfiguration) async throws -> String {
        try await ensureValidToken()
        let projectId = try await resolveProjectId(for: listName)

        var body: [String: Any] = [
            "title": task.title,
            "priority": mapPriorityToTickTick(task.priority)
        ]

        if let projectId = projectId {
            body["projectId"] = projectId
        }

        if let dueDate = task.dueDate {
            body["dueDate"] = ISO8601DateFormatter().string(from: dueDate)
            body["isAllDay"] = !config.includeDueTime
        }

        if let notes = task.notes, !notes.isEmpty {
            body["content"] = notes
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await makeRequest(method: "POST", path: "/task", body: jsonData)
        let created = try JSONDecoder().decode(TickTickTask.self, from: data)

        if task.isCompleted, let pid = created.projectId {
            try await completeTask(projectId: pid, taskId: created.id)
        }

        debugLog("[TickTick] Created task \"\(task.title)\" with id=\(created.id)")
        return created.id
    }

    func updateTask(withId id: String, from task: SyncTask, config: SyncConfiguration) async throws {
        try await ensureValidToken()

        var body: [String: Any] = [
            "title": task.title,
            "priority": mapPriorityToTickTick(task.priority)
        ]

        if let dueDate = task.dueDate {
            body["dueDate"] = ISO8601DateFormatter().string(from: dueDate)
            body["isAllDay"] = !config.includeDueTime
        }

        if let notes = task.notes {
            body["content"] = notes
        }

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        try await makeRequest(method: "POST", path: "/task/\(id)", body: jsonData)
    }

    func moveTask(withId id: String, toList listName: String) async throws {
        // TickTick doesn't have a direct move endpoint in the Open API.
        // The task's projectId can be updated via the update endpoint.
        try await ensureValidToken()
        guard let projectId = try await resolveProjectId(for: listName) else {
            throw TickTickError.projectNotFound(listName)
        }

        let body: [String: Any] = ["projectId": projectId]
        let jsonData = try JSONSerialization.data(withJSONObject: body)
        try await makeRequest(method: "POST", path: "/task/\(id)", body: jsonData)
    }

    func deleteTask(withId id: String) async throws {
        try await ensureValidToken()
        // TickTick delete is project-scoped. We need the projectId.
        // Try to find it from cached data, or use the task endpoint.
        let projects = try await fetchProjects()
        for project in projects {
            // Try deleting from each project — the API will succeed for the correct one
            do {
                try await makeRequest(method: "DELETE", path: "/project/\(project.id)/task/\(id)")
                return
            } catch {
                continue
            }
        }
        throw TickTickError.apiError(404, "Task \(id) not found in any project")
    }

    func refresh() {
        cachedProjects = []
        lastProjectRefresh = nil
    }

    // MARK: - OAuth

    /// Initiate the OAuth flow by opening the browser.
    func startOAuthFlow() {
        let authURL = "https://ticktick.com/oauth/authorize?client_id=\(Self.clientId)&redirect_uri=\(Self.redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Self.redirectURI)&response_type=code&scope=tasks:read%20tasks:write"
        if let url = URL(string: authURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Exchange an authorization code for access/refresh tokens.
    func exchangeCodeForToken(_ code: String) async throws {
        let tokenURL = URL(string: "https://ticktick.com/oauth/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Basic auth with client_id:client_secret
        let credentials = "\(Self.clientId):\(Self.clientSecret)"
        let base64 = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")

        let bodyStr = "code=\(code)&grant_type=authorization_code&redirect_uri=\(Self.redirectURI)"
        request.httpBody = bodyStr.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TickTickError.oauthFailed("Token exchange failed")
        }

        let tokenResponse = try JSONDecoder().decode(TickTickTokenResponse.self, from: data)
        accessToken = tokenResponse.accessToken
        refreshToken = tokenResponse.refreshToken ?? ""
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 86400))
    }

    // MARK: - Private Helpers

    private func ensureValidToken() async throws {
        guard !accessToken.isEmpty else {
            throw TickTickError.notConnected
        }
        guard let expiry = tokenExpiry, Date() >= expiry.addingTimeInterval(-60) else { return }

        // Token expired or about to expire — refresh
        guard !refreshToken.isEmpty else {
            throw TickTickError.tokenExpired
        }

        let tokenURL = URL(string: "https://ticktick.com/oauth/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = "\(Self.clientId):\(Self.clientSecret)"
        let base64 = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")

        let bodyStr = "refresh_token=\(refreshToken)&grant_type=refresh_token"
        request.httpBody = bodyStr.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TickTickError.tokenExpired
        }

        let tokenResponse = try JSONDecoder().decode(TickTickTokenResponse.self, from: data)
        accessToken = tokenResponse.accessToken
        if let newRefresh = tokenResponse.refreshToken {
            refreshToken = newRefresh
        }
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn ?? 86400))
    }

    private func fetchProjects() async throws -> [TickTickProject] {
        let (data, _) = try await makeRequest(method: "GET", path: "/project")
        return try JSONDecoder().decode([TickTickProject].self, from: data)
    }

    private func fetchTasksInProject(_ project: TickTickProject) async throws -> [SyncTask] {
        let (data, _) = try await makeRequest(method: "GET", path: "/project/\(project.id)/data")
        let projectData = try JSONDecoder().decode(TickTickProjectData.self, from: data)

        return (projectData.tasks ?? []).map { task in
            mapToSyncTask(task, projectName: project.name)
        }
    }

    private func completeTask(projectId: String, taskId: String) async throws {
        try await makeRequest(method: "POST", path: "/project/\(projectId)/task/\(taskId)/complete")
    }

    private func resolveProjectId(for listName: String) async throws -> String? {
        let projects = try await fetchProjects()
        return projects.first(where: { $0.name.lowercased() == listName.lowercased() })?.id
    }

    @discardableResult
    private func makeRequest(method: String, path: String, body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        guard !accessToken.isEmpty else {
            throw TickTickError.notConnected
        }

        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TickTickError.apiError(0, "Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return (data, httpResponse)
        case 401:
            throw TickTickError.tokenExpired
        case 429:
            throw TickTickError.apiError(429, "Rate limited")
        default:
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw TickTickError.apiError(httpResponse.statusCode, snippet)
        }
    }

    // MARK: - Mapping

    private func mapToSyncTask(_ task: TickTickTask, projectName: String) -> SyncTask {
        let priority = mapPriorityFromTickTick(task.priority)
        let dueDate = task.dueDate.flatMap { ISO8601DateFormatter().date(from: $0) }
        let isCompleted = task.status == 2

        return SyncTask(
            title: task.title,
            isCompleted: isCompleted,
            priority: priority,
            dueDate: dueDate,
            tags: [],  // TickTick Open API doesn't support tags
            targetList: projectName,
            notes: task.content?.isEmpty == false ? task.content : nil,
            remindersId: task.id,
            lastModified: Date()
        )
    }

    private func mapPriorityToTickTick(_ priority: SyncTask.Priority) -> Int {
        switch priority {
        case .high: return 5
        case .medium: return 3
        case .low: return 1
        case .none: return 0
        }
    }

    private func mapPriorityFromTickTick(_ priority: Int) -> SyncTask.Priority {
        switch priority {
        case 5: return .high
        case 3: return .medium
        case 1: return .low
        default: return .none
        }
    }
}

// MARK: - API Models

private struct TickTickTask: Codable {
    let id: String
    let title: String
    let content: String?
    let priority: Int
    let dueDate: String?
    let projectId: String?
    let status: Int  // 0 = normal, 2 = completed
}

private struct TickTickProject: Codable {
    let id: String
    let name: String
}

private struct TickTickProjectData: Codable {
    let tasks: [TickTickTask]?
}

private struct TickTickTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Errors

enum TickTickError: LocalizedError {
    case notConnected
    case tokenExpired
    case oauthFailed(String)
    case apiError(Int, String)
    case projectNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to TickTick. Please connect your account in Settings."
        case .tokenExpired:
            return "TickTick session expired. Please reconnect your account in Settings."
        case .oauthFailed(let message):
            return "TickTick OAuth error: \(message)"
        case .apiError(let code, let message):
            return "TickTick API error (HTTP \(code)): \(message)"
        case .projectNotFound(let name):
            return "TickTick project not found: \(name)"
        }
    }
}
