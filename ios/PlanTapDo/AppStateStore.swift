import Foundation

struct WorkspaceState: Codable {
    var todos: [TodoEntry]
    var categories: [Category]
    var locationTravelTimes: [String: Int]
    var focusBlocks: [FocusBlock]
    var needsCloudSync: Bool
    var deletedTodoIDs: Set<UUID>
    var deletedCategoryIDs: Set<UUID>
    var deletedSessionIDs: Set<UUID>

    static let empty = WorkspaceState(
        todos: [],
        categories: [],
        locationTravelTimes: [:],
        focusBlocks: [],
        needsCloudSync: false,
        deletedTodoIDs: [],
        deletedCategoryIDs: [],
        deletedSessionIDs: []
    )

    private enum CodingKeys: String, CodingKey {
        case todos
        case categories
        case locationTravelTimes
        case focusBlocks
        case timeSessionsByTodoID
        case needsCloudSync
        case deletedTodoIDs
        case deletedCategoryIDs
        case deletedSessionIDs
    }

    init(
        todos: [TodoEntry],
        categories: [Category],
        locationTravelTimes: [String: Int],
        focusBlocks: [FocusBlock],
        needsCloudSync: Bool = false,
        deletedTodoIDs: Set<UUID> = [],
        deletedCategoryIDs: Set<UUID> = [],
        deletedSessionIDs: Set<UUID> = []
    ) {
        self.todos = todos
        self.categories = categories
        self.locationTravelTimes = locationTravelTimes
        self.focusBlocks = focusBlocks
        self.needsCloudSync = needsCloudSync
        self.deletedTodoIDs = deletedTodoIDs
        self.deletedCategoryIDs = deletedCategoryIDs
        self.deletedSessionIDs = deletedSessionIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // New workspace sections must not make an older on-device state file
        // undecodable. A missing key represents the empty state introduced by
        // that version of the app.
        todos = try container.decodeIfPresent([TodoEntry].self, forKey: .todos) ?? []
        categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? []
        locationTravelTimes = try container.decodeIfPresent(
            [String: Int].self,
            forKey: .locationTravelTimes
        ) ?? [:]
        focusBlocks = try container.decodeIfPresent([FocusBlock].self, forKey: .focusBlocks) ?? []
        needsCloudSync = try container.decodeIfPresent(Bool.self, forKey: .needsCloudSync) ?? false
        deletedTodoIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .deletedTodoIDs) ?? []
        deletedCategoryIDs = try container.decodeIfPresent(
            Set<UUID>.self,
            forKey: .deletedCategoryIDs
        ) ?? []
        deletedSessionIDs = try container.decodeIfPresent(
            Set<UUID>.self,
            forKey: .deletedSessionIDs
        ) ?? []
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
        try container.encode(needsCloudSync, forKey: .needsCloudSync)
        try container.encode(deletedTodoIDs, forKey: .deletedTodoIDs)
        try container.encode(deletedCategoryIDs, forKey: .deletedCategoryIDs)
        try container.encode(deletedSessionIDs, forKey: .deletedSessionIDs)
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
    private var backupFileURL: URL {
        fileURL.appendingPathExtension("backup")
    }

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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for candidateURL in [fileURL, backupFileURL] {
            guard let data = try? Data(contentsOf: candidateURL),
                  let state = try? decoder.decode(PersistedAppState.self, from: data) else {
                continue
            }
            return state
        }
        return nil
    }

    func save(_ state: PersistedAppState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var protectedDirectoryURL = directoryURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try protectedDirectoryURL.setResourceValues(resourceValues)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        // Keep an independently replaceable copy so a damaged primary state
        // file does not turn into an empty workspace on the next launch.
        try data.write(to: backupFileURL, options: [.atomic, .completeFileProtection])
    }
}
