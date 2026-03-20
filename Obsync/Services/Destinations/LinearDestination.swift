import Foundation

/// Linear destination using the GraphQL API.
///
/// Architecture:
/// - AUTH: Personal API key (Authorization header)
/// - READ: GraphQL query for issues
/// - CREATE: GraphQL mutation issueCreate
/// - UPDATE: GraphQL mutation issueUpdate
/// - COMPLETE: issueUpdate with stateId for "Done"
/// - DELETE: GraphQL mutation issueDelete
///
/// API docs: https://developers.linear.app/docs/graphql/working-with-the-graphql-api
class LinearDestination: TaskDestination {
    let destinationName = "Linear"

    var apiKey: String = ""

    private let apiURL = "https://api.linear.app/graphql"
    private let session = URLSession.shared

    // Cache
    private var cachedTeams: [LinearTeam] = []
    private var cachedStates: [LinearWorkflowState] = []
    private var lastRefreshDate: Date?

    // MARK: - Authorization

    func requestAccess() async throws -> Bool {
        guard !apiKey.isEmpty else {
            throw LinearError.invalidApiKey
        }
        // Verify key by fetching viewer
        let query = """
        { viewer { id name } }
        """
        let (data, response) = try await makeGraphQLRequest(query: query)
        guard response.statusCode == 200 else { return false }
        // Check for errors in GraphQL response
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            return false
        }
        return true
    }

    // MARK: - Fetching

    func fetchAllTasks() async throws -> [SyncTask] {
        // Fetch workflow states for mapping
        try await refreshStatesIfNeeded()

        var allIssues: [LinearIssue] = []
        var hasMore = true
        var cursor: String? = nil

        while hasMore {
            let afterClause = cursor.map { ", after: \"\($0)\"" } ?? ""
            let query = """
            {
                issues(first: 100\(afterClause), filter: { assignee: { isMe: { eq: true } } }) {
                    nodes {
                        id
                        title
                        description
                        priority
                        dueDate
                        completedAt
                        state { id name type }
                        team { id name }
                        labels { nodes { name } }
                    }
                    pageInfo { hasNextPage endCursor }
                }
            }
            """

            let (data, _) = try await makeGraphQLRequest(query: query)
            let result = try JSONDecoder().decode(LinearIssuesResponse.self, from: data)

            if let errors = result.errors, !errors.isEmpty {
                throw LinearError.graphQLError(errors.map { $0.message }.joined(separator: "; "))
            }

            guard let issues = result.data?.issues else {
                throw LinearError.graphQLError("No issues data in response")
            }

            allIssues.append(contentsOf: issues.nodes)
            hasMore = issues.pageInfo.hasNextPage
            cursor = issues.pageInfo.endCursor
        }

        debugLog("[Linear] Fetched \(allIssues.count) issues")
        return allIssues.map { mapToSyncTask($0) }
    }

    func getAvailableLists() async -> [String] {
        if let lastRefresh = lastRefreshDate, Date().timeIntervalSince(lastRefresh) < 60 {
            return cachedTeams.map { $0.name }
        }
        do {
            try await refreshTeams()
            return cachedTeams.map { $0.name }
        } catch {
            debugLog("[Linear] Failed to fetch teams: \(error)")
            return cachedTeams.map { $0.name }
        }
    }

    // MARK: - CRUD

    func createTask(from task: SyncTask, inList listName: String, config: SyncConfiguration) async throws -> String {
        let teamId = try await resolveTeamId(for: listName)

        var fields: [String] = [
            "title: \"\(escapeGraphQL(task.title))\"",
            "teamId: \"\(teamId)\""
        ]

        if let dueDate = task.dueDate {
            fields.append("dueDate: \"\(formatDate(dueDate))\"")
        }

        if let notes = task.notes, !notes.isEmpty {
            fields.append("description: \"\(escapeGraphQL(notes))\"")
        }

        let priorityValue = mapPriorityToLinear(task.priority)
        if priorityValue > 0 {
            fields.append("priority: \(priorityValue)")
        }

        // If completed, find the "Done" state for the team
        if task.isCompleted {
            if let doneStateId = try await findDoneStateId(teamId: teamId) {
                fields.append("stateId: \"\(doneStateId)\"")
            }
        }

        let mutation = """
        mutation {
            issueCreate(input: { \(fields.joined(separator: ", ")) }) {
                success
                issue { id title }
            }
        }
        """

        let (data, _) = try await makeGraphQLRequest(query: mutation)
        let result = try JSONDecoder().decode(LinearCreateResponse.self, from: data)

        guard let issue = result.data?.issueCreate?.issue else {
            let errorMsg = result.errors?.map { $0.message }.joined(separator: "; ") ?? "Unknown error"
            throw LinearError.graphQLError(errorMsg)
        }

        debugLog("[Linear] Created issue \"\(task.title)\" with id=\(issue.id)")
        return issue.id
    }

    func updateTask(withId id: String, from task: SyncTask, config: SyncConfiguration) async throws {
        var fields: [String] = [
            "title: \"\(escapeGraphQL(task.title))\""
        ]

        if let dueDate = task.dueDate {
            fields.append("dueDate: \"\(formatDate(dueDate))\"")
        } else {
            fields.append("dueDate: null")
        }

        if let notes = task.notes {
            fields.append("description: \"\(escapeGraphQL(notes))\"")
        }

        let priorityValue = mapPriorityToLinear(task.priority)
        fields.append("priority: \(priorityValue)")

        let mutation = """
        mutation {
            issueUpdate(id: \"\(id)\", input: { \(fields.joined(separator: ", ")) }) {
                success
            }
        }
        """

        try await makeGraphQLRequest(query: mutation)
    }

    func moveTask(withId id: String, toList listName: String) async throws {
        let teamId = try await resolveTeamId(for: listName)

        let mutation = """
        mutation {
            issueUpdate(id: \"\(id)\", input: { teamId: \"\(teamId)\" }) {
                success
            }
        }
        """

        try await makeGraphQLRequest(query: mutation)
    }

    func deleteTask(withId id: String) async throws {
        let mutation = """
        mutation {
            issueDelete(id: \"\(id)\") {
                success
            }
        }
        """

        try await makeGraphQLRequest(query: mutation)
    }

    func refresh() {
        cachedTeams = []
        cachedStates = []
        lastRefreshDate = nil
    }

    // MARK: - Private Helpers

    private func refreshTeams() async throws {
        let query = """
        { teams { nodes { id name } } }
        """
        let (data, _) = try await makeGraphQLRequest(query: query)
        let result = try JSONDecoder().decode(LinearTeamsResponse.self, from: data)
        cachedTeams = result.data?.teams?.nodes ?? []
        lastRefreshDate = Date()
    }

    private func refreshStatesIfNeeded() async throws {
        guard cachedStates.isEmpty else { return }
        let query = """
        { workflowStates { nodes { id name type team { id } } } }
        """
        let (data, _) = try await makeGraphQLRequest(query: query)
        let result = try JSONDecoder().decode(LinearStatesResponse.self, from: data)
        cachedStates = result.data?.workflowStates?.nodes ?? []
    }

    private func resolveTeamId(for listName: String) async throws -> String {
        if cachedTeams.isEmpty {
            try await refreshTeams()
        }
        guard let team = cachedTeams.first(where: { $0.name.lowercased() == listName.lowercased() }) else {
            // Use first team as fallback
            guard let firstTeam = cachedTeams.first else {
                throw LinearError.noTeams
            }
            return firstTeam.id
        }
        return team.id
    }

    private func findDoneStateId(teamId: String) async throws -> String? {
        try await refreshStatesIfNeeded()
        return cachedStates.first(where: { $0.type == "completed" && $0.team?.id == teamId })?.id
    }

    @discardableResult
    private func makeGraphQLRequest(query: String, retryCount: Int = 0) async throws -> (Data, HTTPURLResponse) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw LinearError.invalidApiKey
        }

        let url = URL(string: apiURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(cleanKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        debugLog("[Linear] GraphQL query: \(query.prefix(100))...")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LinearError.apiError(0, "Invalid response")
        }

        debugLog("[Linear] GraphQL -> HTTP \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200...299:
            return (data, httpResponse)
        case 401:
            throw LinearError.invalidApiKey
        case 429:
            if retryCount < 2 {
                let retryAfter = Double(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "5") ?? 5
                debugLog("[Linear] Rate limited, retrying after \(retryAfter)s")
                try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                return try await makeGraphQLRequest(query: query, retryCount: retryCount + 1)
            }
            throw LinearError.rateLimited
        case 500...599:
            if retryCount < 1 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return try await makeGraphQLRequest(query: query, retryCount: retryCount + 1)
            }
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw LinearError.serverError(httpResponse.statusCode, snippet)
        default:
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw LinearError.apiError(httpResponse.statusCode, snippet)
        }
    }

    // MARK: - Mapping

    private func mapToSyncTask(_ issue: LinearIssue) -> SyncTask {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let dueDate = issue.dueDate.flatMap { dateFormatter.date(from: $0) }
        let isCompleted = issue.state?.type == "completed" || issue.state?.type == "cancelled"
        let completedAt = issue.completedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        let teamName = issue.team?.name ?? ""
        let priority = mapPriorityFromLinear(issue.priority)
        let tags = issue.labels?.nodes.map { "#\($0.name)" } ?? []

        return SyncTask(
            title: issue.title,
            isCompleted: isCompleted,
            priority: priority,
            dueDate: dueDate,
            completedDate: completedAt,
            tags: tags,
            targetList: teamName.isEmpty ? nil : teamName,
            notes: issue.description,
            remindersId: issue.id,
            lastModified: Date()
        )
    }

    private func mapPriorityToLinear(_ priority: SyncTask.Priority) -> Int {
        // Linear: 0=No priority, 1=Urgent, 2=High, 3=Medium, 4=Low
        switch priority {
        case .high: return 2
        case .medium: return 3
        case .low: return 4
        case .none: return 0
        }
    }

    private func mapPriorityFromLinear(_ priority: Int) -> SyncTask.Priority {
        switch priority {
        case 1, 2: return .high
        case 3: return .medium
        case 4: return .low
        default: return .none
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func escapeGraphQL(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

// MARK: - GraphQL Response Models

private struct LinearIssuesResponse: Codable {
    let data: LinearIssuesData?
    let errors: [LinearGraphQLError]?
}

private struct LinearIssuesData: Codable {
    let issues: LinearIssueConnection?
}

private struct LinearIssueConnection: Codable {
    let nodes: [LinearIssue]
    let pageInfo: LinearPageInfo
}

private struct LinearPageInfo: Codable {
    let hasNextPage: Bool
    let endCursor: String?
}

private struct LinearIssue: Codable {
    let id: String
    let title: String
    let description: String?
    let priority: Int
    let dueDate: String?
    let completedAt: String?
    let state: LinearState?
    let team: LinearTeamRef?
    let labels: LinearLabelConnection?
}

private struct LinearState: Codable {
    let id: String
    let name: String
    let type: String  // "backlog", "unstarted", "started", "completed", "cancelled"
}

private struct LinearTeamRef: Codable {
    let id: String
    let name: String
}

private struct LinearLabelConnection: Codable {
    let nodes: [LinearLabel]
}

private struct LinearLabel: Codable {
    let name: String
}

private struct LinearCreateResponse: Codable {
    let data: LinearCreateData?
    let errors: [LinearGraphQLError]?
}

private struct LinearCreateData: Codable {
    let issueCreate: LinearIssueCreatePayload?
}

private struct LinearIssueCreatePayload: Codable {
    let success: Bool
    let issue: LinearCreatedIssue?
}

private struct LinearCreatedIssue: Codable {
    let id: String
    let title: String
}

private struct LinearTeamsResponse: Codable {
    let data: LinearTeamsData?
}

private struct LinearTeamsData: Codable {
    let teams: LinearTeamConnection?
}

private struct LinearTeamConnection: Codable {
    let nodes: [LinearTeam]
}

private struct LinearTeam: Codable {
    let id: String
    let name: String
}

private struct LinearStatesResponse: Codable {
    let data: LinearStatesData?
}

private struct LinearStatesData: Codable {
    let workflowStates: LinearStateConnection?
}

private struct LinearStateConnection: Codable {
    let nodes: [LinearWorkflowState]
}

private struct LinearWorkflowState: Codable {
    let id: String
    let name: String
    let type: String
    let team: LinearTeamRef?
}

private struct LinearGraphQLError: Codable {
    let message: String
}

// MARK: - Errors

enum LinearError: LocalizedError {
    case invalidApiKey
    case noTeams
    case rateLimited
    case graphQLError(String)
    case apiError(Int, String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidApiKey:
            return "Invalid Linear API key. Get your key from Linear > Settings > API > Personal API Keys."
        case .noTeams:
            return "No Linear teams found. Make sure your account belongs to at least one team."
        case .rateLimited:
            return "Linear API rate limit exceeded. Please wait a moment and try again."
        case .graphQLError(let message):
            return "Linear GraphQL error: \(message)"
        case .apiError(let code, let message):
            return "Linear API error (HTTP \(code)): \(message)"
        case .serverError(let code, let message):
            return "Linear server error (HTTP \(code)). Try again in a moment. \(message)"
        }
    }
}
