import Foundation

struct WorkspaceState: Codable {
    var todos: [TodoEntry]
    var categories: [Category]
    var locationTravelTimes: [String: Int]
    var focusBlocks: [FocusBlock]

    static let empty = WorkspaceState(
        todos: [],
        categories: [],
        locationTravelTimes: [:],
        focusBlocks: []
    )

    private enum CodingKeys: String, CodingKey {
        case todos
        case categories
        case locationTravelTimes
        case focusBlocks
        case timeSessionsByTodoID
    }

    init(
        todos: [TodoEntry],
        categories: [Category],
        locationTravelTimes: [String: Int],
        focusBlocks: [FocusBlock]
    ) {
        self.todos = todos
        self.categories = categories
        self.locationTravelTimes = locationTravelTimes
        self.focusBlocks = focusBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        todos = try container.decode([TodoEntry].self, forKey: .todos)
        categories = try container.decode([Category].self, forKey: .categories)
        locationTravelTimes = try container.decode(
            [String: Int].self,
            forKey: .locationTravelTimes
        )
        focusBlocks = try container.decode([FocusBlock].self, forKey: .focusBlocks)
        let sessions = try container.decodeIfPresent(
            [UUID: [TimeSession]].self,
            forKey: .timeSessionsByTodoID
        ) ?? [:]
        for index in todos.indices {
            todos[index].timeSessions = sessions[todos[index].id]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(todos, forKey: .todos)
        try container.encode(categories, forKey: .categories)
        try container.encode(locationTravelTimes, forKey: .locationTravelTimes)
        try container.encode(focusBlocks, forKey: .focusBlocks)
        let sessions = Dictionary(
            todos.compactMap { todo in
                todo.timeSessions.map { (todo.id, $0) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        try container.encode(sessions, forKey: .timeSessionsByTodoID)
    }
}

struct PersistedAppState: Codable {
    var accounts: [UserAccount]
    var activeAccountID: UUID
    var workspaces: [UUID: WorkspaceState]
}

struct AppStateStore {
    private let fileURL: URL

    static let live: AppStateStore = {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return AppStateStore(fileURL: baseURL
            .appendingPathComponent("PlanTapDo", isDirectory: true)
            .appendingPathComponent("app-state.json"))
    }()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> PersistedAppState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedAppState.self, from: data)
    }

    func save(_ state: PersistedAppState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
