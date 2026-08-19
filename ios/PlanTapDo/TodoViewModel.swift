// TodoViewModel.swift
import Foundation
import Combine
import SwiftUI

enum DisplayStyle: String, CaseIterable {
    case list = "List"
    case calendar = "Calendar"
}

class TodoViewModel: ObservableObject {
    @Published var userAccount: UserAccount {
        didSet { persistAppState() }
    }
    @Published var availableAccounts: [UserAccount] = [] {
        didSet { persistAppState() }
    }
    @Published var todos: [TodoEntry] = [] {
        didSet { persistAppState() }
    }
    @Published var categories: [Category] = [] {
        didSet { persistAppState() }
    }
    @Published var teamReviewPeople: [UserAccount] = []
    @Published var locationTravelTimes: [String: Int] = [:] {
        didSet { persistAppState() }
    }
    @Published var focusBlocks: [FocusBlock] = [] {
        didSet { persistAppState() }
    }
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    // UI State
    @Published var selectedTab: Int = 0 // 0: Today, 1: Future, 2: Categories, 3: Settings
    @Published var displayStyle: DisplayStyle = .list
    @Published var selectedFutureDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @Published var currentWeekOffset: Int = 0
    @Published var theme: AppTheme = AppTheme(
        rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? ""
    ) ?? .dark {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "appTheme") }
    }
    @Published var showCompletedTasks: Bool {
        didSet { UserDefaults.standard.set(showCompletedTasks, forKey: "showCompletedTasks") }
    }

    // MARK: - Timer State
    @Published var activeTimerTodoId: UUID? = nil
    @Published var timerSecondsElapsed: Int = 0
    @Published private(set) var startUndoTitle: String?
    private var timer: Timer? = nil
    private var activeTimerSessionId: UUID? = nil
    private var serverSessionIds: [UUID: UUID] = [:]
    private var cancelledSessionIds = Set<UUID>()
    private var todoMutationVersions: [UUID: Int] = [:]

    private var localWorkspaces: [UUID: WorkspaceState] = [:]

    private struct StartUndoSnapshot {
        let todo: TodoEntry
        let sessionId: UUID
    }

    private var startUndoSnapshot: StartUndoSnapshot?
    private var startUndoTimer: Timer?

    var canUndoLastStart: Bool { startUndoSnapshot != nil }
    var isProReviewDemo: Bool { userAccount.tier == "Pro Demo" }

    var timerFormatted: String {
        let mins = timerSecondsElapsed / 60
        let secs = timerSecondsElapsed % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    func startTimer(for todo: TodoEntry) {
        if activeTimerTodoId != nil {
            stopTimer()
        }
        if let idx = todos.firstIndex(where: { $0.id == todo.id }) {
            let now = Date()
            let originalTodo = todos[idx]
            let session = TimeSession(
                id: UUID(),
                todoId: todo.id,
                start: now,
                end: nil,
                duration: nil
            )
            startUndoSnapshot = StartUndoSnapshot(todo: originalTodo, sessionId: session.id)
            startUndoTitle = originalTodo.title
            scheduleStartUndoExpiry()

            todos[idx].status = .inProgress
            todos[idx].doDate = Calendar.current.startOfDay(for: now)
            todos[idx].plannedStartTime = Self.timeString(from: min(23 * 60 + 55, Self.roundedUpToFiveMinutes(now)))
            var sessions = todos[idx].timeSessions ?? []
            sessions.append(session)
            todos[idx].timeSessions = sessions
            activeTimerTodoId = todo.id
            activeTimerSessionId = session.id
            persistTodo(todos[idx])
            persistSessionStart(session)
        }
        timerSecondsElapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.timerSecondsElapsed += 1
            }
        }
    }

    func stopTimer() {
        if let activeId = activeTimerTodoId, let idx = todos.firstIndex(where: { $0.id == activeId }) {
            todos[idx].status = .inProgress
            if let sessionId = activeTimerSessionId,
               var sessions = todos[idx].timeSessions,
               let sessionIndex = sessions.firstIndex(where: { $0.id == sessionId }) {
                let end = Date()
                sessions[sessionIndex].end = end
                sessions[sessionIndex].duration = end.timeIntervalSince(sessions[sessionIndex].start)
                todos[idx].timeSessions = sessions
                persistSessionEnd(sessions[sessionIndex])
            }
            persistTodo(todos[idx])
        }
        clearTimerState()
        clearStartUndo()
    }

    func undoLastStart() {
        guard let snapshot = startUndoSnapshot else { return }

        timer?.invalidate()
        timer = nil
        activeTimerTodoId = nil
        activeTimerSessionId = nil
        timerSecondsElapsed = 0

        if let index = todos.firstIndex(where: { $0.id == snapshot.todo.id }) {
            todos[index] = snapshot.todo
            persistTodo(snapshot.todo)
        }
        cancelSession(id: snapshot.sessionId)
        clearStartUndo()
    }

    private func clearTimerState() {
        timer?.invalidate()
        timer = nil
        activeTimerTodoId = nil
        activeTimerSessionId = nil
        timerSecondsElapsed = 0
    }

    private func clearStartUndo() {
        startUndoTimer?.invalidate()
        startUndoTimer = nil
        startUndoSnapshot = nil
        startUndoTitle = nil
    }

    private func scheduleStartUndoExpiry() {
        startUndoTimer?.invalidate()
        startUndoTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: false) { [weak self] _ in
            self?.clearStartUndo()
        }
    }


    private var cancellables = Set<AnyCancellable>()
    private let api = APIClient.shared
    private let stateStore: AppStateStore
    private let credentialStore: CredentialStore
    private var isRestoringState = true

    init(
        stateStore: AppStateStore = .live,
        credentialStore: CredentialStore = .shared
    ) {
        self.stateStore = stateStore
        self.credentialStore = credentialStore

        let personalAccount = UserAccount(
            id: UUID(),
            name: "Personal Account",
            email: "personal@plantapdo.app",
            tier: "Personal",
            isCloudSynced: false
        )
        let proReviewAccount = UserAccount(
            id: UUID(),
            name: "Pro Team Review",
            email: "pro-demo@plantapdo.app",
            tier: "Pro Demo",
            isCloudSynced: false
        )
        let fallbackAccounts = [personalAccount, proReviewAccount]
        let persistedState = stateStore.load()
        let restoredAccounts = persistedState?.accounts.isEmpty == false
            ? persistedState!.accounts
            : fallbackAccounts
        let restoredAccount = restoredAccounts.first {
            $0.id == persistedState?.activeAccountID
        } ?? restoredAccounts[0]

        self.userAccount = restoredAccount
        self.availableAccounts = restoredAccounts
        self.showCompletedTasks = UserDefaults.standard.bool(forKey: "showCompletedTasks")
        self.localWorkspaces = persistedState?.workspaces ?? [personalAccount.id: .empty]

        if restoredAccount.tier != "Pro Demo" {
            let workspace = localWorkspaces[restoredAccount.id] ?? .empty
            self.todos = workspace.todos
            self.categories = workspace.categories
            self.locationTravelTimes = workspace.locationTravelTimes
            self.focusBlocks = workspace.focusBlocks
        }

        isRestoringState = false
        api.onTokensChanged = { [weak self] tokens in
            DispatchQueue.main.async {
                guard let self, self.userAccount.isCloudSynced else { return }
                if let tokens {
                    self.credentialStore.save(tokens, accountID: self.userAccount.id)
                } else {
                    self.credentialStore.delete(accountID: self.userAccount.id)
                    self.errorMessage = "Your session expired. Sign in again to resume cloud sync."
                }
            }
        }

        if restoredAccount.tier == "Pro Demo" {
            loadProReviewDemoData()
        } else if restoredAccount.isCloudSynced,
                  let tokens = credentialStore.load(accountID: restoredAccount.id) {
            api.setAuthTokens(tokens, notify: false)
        } else {
            api.clearAuthTokens(notify: false)
        }
        persistAppState()
    }

    func shouldDisplay(_ todo: TodoEntry) -> Bool {
        showCompletedTasks || (todo.status != .completed && todo.status != .archived && todo.status != .skipped)
    }

    func todos(on date: Date, categoryId: UUID? = nil) -> [TodoEntry] {
        todos.filter {
            Calendar.current.isDate($0.doDate, inSameDayAs: date)
                && (categoryId == nil || $0.categoryId == categoryId)
                && shouldDisplay($0)
        }
        .sorted {
            let leftTime = $0.plannedStartTime ?? "23:59"
            let rightTime = $1.plannedStartTime ?? "23:59"
            if leftTime == rightTime {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return leftTime < rightTime
        }
    }

    private func makeLocationKey(_ locA: String, _ locB: String) -> String {
        let a = locA.trimmingCharacters(in: .whitespaces).lowercased()
        let b = locB.trimmingCharacters(in: .whitespaces).lowercased()
        return a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    func getTravelTimeBetweenLocations(_ locA: String, _ locB: String) -> Int {
        let key = makeLocationKey(locA, locB)
        return locationTravelTimes[key] ?? 15
    }

    func setTravelTimeBetweenLocations(_ locA: String, _ locB: String, durationMinutes: Int) {
        guard !locA.isEmpty && !locB.isEmpty else { return }
        let key = makeLocationKey(locA, locB)
        locationTravelTimes[key] = max(0, min(10_080, durationMinutes))
        guard userAccount.isCloudSynced, api.isAuthenticated else { return }

        api.syncTravelTimes(locationTravelTimes)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] state in
                self?.applyTravelTimes(state.travelTimes)
            }
            .store(in: &cancellables)
    }

    func switchAccount(_ account: UserAccount) {
        saveActiveWorkspace()
        let wasRestoringState = isRestoringState
        isRestoringState = true
        defer {
            isRestoringState = wasRestoringState
            if !wasRestoringState {
                persistAppState()
            }
        }
        clearTimerState()
        clearStartUndo()
        userAccount = account
        if account.tier == "Pro Demo" {
            api.clearAuthTokens(notify: false)
            loadProReviewDemoData()
        } else {
            restoreWorkspace(for: account)
            if account.isCloudSynced,
               let tokens = credentialStore.load(accountID: account.id) {
                api.setAuthTokens(tokens, notify: false)
                fetchTodos()
            } else {
                api.clearAuthTokens(notify: false)
            }
            if account.isCloudSynced && !api.isAuthenticated {
                errorMessage = "Sign in again to resume cloud sync."
            }
        }
    }

    func registerAndSwitchAccount(username: String, email: String, password: String) {
        guard !username.isEmpty && !email.isEmpty && !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        api.registerAccount(username: username, email: email, password: password)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] response in
                guard let self else { return }
                let account = UserAccount(
                    id: response.id,
                    name: response.username,
                    email: response.email,
                    tier: "Cloud",
                    isCloudSynced: true
                )
                self.activateCloudAccount(account, tokens: response.tokens)
            }
            .store(in: &cancellables)
    }

    func loginAndSwitchAccount(username: String, password: String) {
        guard !username.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        api.login(username: username, password: password)
            .flatMap { [api] tokens in
                api.setAuthTokens(tokens, notify: false)
                return api.fetchProfile().map { (tokens, $0) }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case let .failure(error) = completion {
                    self?.api.clearAuthTokens(notify: false)
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] tokens, profile in
                guard let self else { return }
                let account = UserAccount(
                    id: profile.id,
                    name: profile.username,
                    email: profile.email,
                    tier: "Cloud",
                    isCloudSynced: true
                )
                self.activateCloudAccount(account, tokens: tokens)
            }
            .store(in: &cancellables)
    }

    func signOutCloudAccount() {
        guard userAccount.isCloudSynced else { return }
        let signedOutID = userAccount.id
        api.logout()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        credentialStore.delete(accountID: signedOutID)
        api.clearAuthTokens(notify: false)
        availableAccounts.removeAll { $0.id == signedOutID }
        guard let fallback = availableAccounts.first(where: { !$0.isCloudSynced }) else { return }
        switchAccount(fallback)
        localWorkspaces.removeValue(forKey: signedOutID)
        persistAppState()
    }

    private func activateCloudAccount(_ account: UserAccount, tokens: APIClient.AuthTokens) {
        saveActiveWorkspace()
        let wasRestoringState = isRestoringState
        isRestoringState = true
        availableAccounts.removeAll { $0.id == account.id }
        availableAccounts.append(account)
        userAccount = account
        restoreWorkspace(for: account)
        teamReviewPeople = []
        isRestoringState = wasRestoringState
        credentialStore.save(tokens, accountID: account.id)
        api.setAuthTokens(tokens, notify: false)
        if !wasRestoringState {
            persistAppState()
        }
        fetchTodos()
    }

    // MARK: - Local Pro Review Demo
    func loadProReviewDemoData() {
        let alex = UserAccount(id: UUID(), name: "Alex Morgan", email: "alex@northstar.demo", tier: "Team Member", isCloudSynced: false)
        let priya = UserAccount(id: UUID(), name: "Priya Shah", email: "priya@northstar.demo", tier: "Team Member", isCloudSynced: false)
        let mateo = UserAccount(id: UUID(), name: "Mateo Ruiz", email: "mateo@northstar.demo", tier: "Team Member", isCloudSynced: false)
        self.teamReviewPeople = [alex, priya, mateo]

        let catWork = Category(id: UUID(), name: "Work & Projects", colorHex: "7C6FF7", icon: "💼")
        let catPersonal = Category(id: UUID(), name: "Personal & Life", colorHex: "3ECF8E", icon: "🏡")
        let catHealth = Category(id: UUID(), name: "Health & Fitness", colorHex: "F5A623", icon: "🏋️")
        let catLearning = Category(id: UUID(), name: "Learning & Skills", colorHex: "60A5FA", icon: "📚")

        self.categories = [catWork, catPersonal, catHealth, catLearning]

        let key1 = makeLocationKey("HQ Office (3rd Floor)", "Equinox Gym")
        let key2 = makeLocationKey("Equinox Gym", "Home Studio")
        let key3 = makeLocationKey("Home Studio", "Coffee Shop")
        self.locationTravelTimes = [
            key1: 20,
            key2: 15,
            key3: 10
        ]

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let dayAfter = Calendar.current.date(byAdding: .day, value: 2, to: today)!
        let nextWeek = Calendar.current.date(byAdding: .day, value: 5, to: today)!
        let calendar = Calendar.current
        func time(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today) ?? today
        }

        self.todos = [
            TodoEntry(
                id: UUID(),
                title: "Review Q3 Product Roadmap & Deliverables",
                description: "Go over feature specs, sprint capacity, and design reviews.",
                doDate: today,
                dueDate: today,
                dueTime: "17:00",
                descriptiveDeadline: "Before EOD client sync",
                plannedStartTime: "09:00",
                plannedDuration: 2700,
                categoryId: catWork.id,
                status: .completed,
                priority: .high,
                location: "HQ Office (3rd Floor)",
                reminder: "15 minutes before",
                labels: ["product", "roadmap"],
                timeSessions: [
                    TimeSession(id: UUID(), start: time(9, 5), end: time(9, 50), duration: 45 * 60)
                ],
                subtasks: [
                    Subtask(id: UUID().uuidString, title: "Check sprint backlog estimates", isCompleted: true),
                    Subtask(id: UUID().uuidString, title: "Verify design mockup deliverables", isCompleted: false),
                    Subtask(id: UUID().uuidString, title: "Draft release timeline email", isCompleted: false)
                ],
                assigneeId: alex.id.uuidString
            ),
            TodoEntry(
                id: UUID(),
                title: "Morning Gym & Cardio Session",
                description: "30 min strength training followed by 15 min cardio intervals.",
                doDate: today,
                dueDate: today,
                dueTime: "10:00",
                descriptiveDeadline: "Before morning standup",
                plannedStartTime: "07:30",
                plannedDuration: 3600,
                categoryId: catHealth.id,
                status: .completed,
                priority: .medium,
                location: "Equinox Gym",
                reminder: "30 minutes before",
                labels: ["health", "fitness"],
                timeSessions: [
                    TimeSession(id: UUID(), start: time(7, 35), end: time(8, 20), duration: 45 * 60)
                ],
                subtasks: [
                    Subtask(id: UUID().uuidString, title: "Stretching & warm up", isCompleted: true),
                    Subtask(id: UUID().uuidString, title: "30m strength workout", isCompleted: true)
                ],
                assigneeId: priya.id.uuidString
            ),
            TodoEntry(
                id: UUID(),
                title: "Design Review & High Contrast Palette",
                description: "Update typography and design tokens for high-contrast accessibility.",
                doDate: today,
                dueDate: today,
                dueTime: "16:00",
                descriptiveDeadline: "Before design review call",
                plannedStartTime: "11:00",
                plannedDuration: 5400,
                categoryId: catWork.id,
                status: .pending,
                priority: .urgent,
                location: "Home Studio",
                reminder: "10 minutes before",
                labels: ["ui-ux", "design"],
                timeSessions: nil,
                subtasks: [
                    Subtask(id: UUID().uuidString, title: "Audit high-contrast tokens", isCompleted: false),
                    Subtask(id: UUID().uuidString, title: "Test 3-day and weekly view modes", isCompleted: false)
                ],
                assigneeId: mateo.id.uuidString
            ),
            TodoEntry(
                id: UUID(),
                title: "Read 2 Chapters of Clean Architecture",
                description: "Take notes on dependency inversion and boundary interfaces.",
                doDate: tomorrow,
                dueDate: tomorrow,
                dueTime: "21:00",
                descriptiveDeadline: "Before bedtime",
                plannedStartTime: "10:00",
                plannedDuration: 1800,
                categoryId: catLearning.id,
                status: .pending,
                priority: .low,
                location: "Coffee Shop",
                reminder: "1 hour before",
                labels: ["reading", "learning"],
                timeSessions: nil,
                subtasks: [],
                assigneeId: priya.id.uuidString
            ),
            TodoEntry(
                id: UUID(),
                title: "Weekly Grocery & Household Supplies",
                description: "Buy organic produce, meal prep ingredients, and household items.",
                doDate: dayAfter,
                dueDate: dayAfter,
                dueTime: "18:00",
                descriptiveDeadline: "Before dinner",
                plannedStartTime: "14:00",
                plannedDuration: 2700,
                categoryId: catPersonal.id,
                status: .pending,
                priority: .medium,
                location: "Whole Foods Market",
                reminder: "30 minutes before",
                labels: ["groceries", "errands"],
                timeSessions: nil,
                subtasks: [],
                assigneeId: alex.id.uuidString
            ),
            TodoEntry(
                id: UUID(),
                title: "Weekly Review & Next Steps",
                description: "Review completed work, blockers, and priorities for next week.",
                doDate: nextWeek,
                dueDate: nextWeek,
                dueTime: "15:00",
                descriptiveDeadline: "Before the week ends",
                plannedStartTime: "14:00",
                plannedDuration: 3600,
                categoryId: catWork.id,
                status: .pending,
                priority: .high,
                location: "HQ Office (3rd Floor)",
                reminder: "15 minutes before",
                labels: ["review", "planning"],
                timeSessions: nil,
                subtasks: [],
                assigneeId: mateo.id.uuidString
            )
        ]
    }

    private func saveActiveWorkspace() {
        guard !isProReviewDemo else { return }
        localWorkspaces[userAccount.id] = WorkspaceState(
            todos: todos,
            categories: categories,
            locationTravelTimes: locationTravelTimes,
            focusBlocks: focusBlocks
        )
    }

    private func restoreWorkspace(for account: UserAccount) {
        let workspace = localWorkspaces[account.id] ?? .empty
        todos = workspace.todos
        categories = workspace.categories
        locationTravelTimes = workspace.locationTravelTimes
        focusBlocks = workspace.focusBlocks
        teamReviewPeople = []
        errorMessage = nil
    }

    private func persistAppState() {
        guard !isRestoringState else { return }
        if !isProReviewDemo {
            localWorkspaces[userAccount.id] = WorkspaceState(
                todos: todos,
                categories: categories,
                locationTravelTimes: locationTravelTimes,
                focusBlocks: focusBlocks
            )
        }
        let state = PersistedAppState(
            accounts: availableAccounts,
            activeAccountID: userAccount.id,
            workspaces: localWorkspaces
        )
        do {
            try stateStore.save(state)
        } catch {
            errorMessage = "Changes are available now but could not be saved on this device."
        }
    }

    // MARK: - Fetch
    func fetchTodos() {
        guard api.isAuthenticated else { return }
        isLoading = true
        errorMessage = nil
        api.fetchSyncState()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] state in
                guard let self else { return }
                self.todos = state.todos
                self.categories = state.categories
                self.applyTravelTimes(state.travelTimes)
                for session in state.sessions {
                    guard let todoId = session.todoId,
                          let index = self.todos.firstIndex(where: { $0.id == todoId }) else { continue }
                    var normalizedSession = session
                    if let duration = normalizedSession.duration {
                        normalizedSession.duration = duration * 60
                    }
                    var sessions = self.todos[index].timeSessions ?? []
                    sessions.append(normalizedSession)
                    self.todos[index].timeSessions = sessions
                }
                self.pushOverdueTasks()
            }
            .store(in: &cancellables)
    }

    func createTodo(
        title: String,
        description: String? = nil,
        doDate: Date = Date(),
        dueDate: Date? = nil,
        dueTime: String? = nil,
        descriptiveDeadline: String? = nil,
        plannedStartTime: String? = nil,
        plannedDuration: TimeInterval = 1800,
        categoryId: UUID? = nil,
        priority: PriorityLevel? = nil,
        location: String? = nil,
        reminder: String? = nil,
        labels: [String]? = nil,
        recurrenceFrequency: RecurrenceFrequency = .none,
        recurrenceWeekdays: [Int]? = nil
    ) {
        let recurrenceSeriesId = recurrenceFrequency == .none ? nil : UUID()
        var newTodo = TodoEntry(
            id: UUID(),
            title: title,
            description: description,
            doDate: doDate,
            dueDate: dueDate,
            dueTime: dueTime,
            descriptiveDeadline: descriptiveDeadline,
            plannedStartTime: plannedStartTime,
            plannedDuration: plannedDuration,
            categoryId: categoryId,
            status: .pending,
            priority: priority,
            location: location,
            reminder: reminder,
            labels: labels,
            timeSessions: nil,
            subtasks: [],
            assigneeId: nil,
            recurrenceFrequency: recurrenceFrequency,
            recurrenceWeekdays: recurrenceWeekdays,
            recurrenceSeriesId: recurrenceSeriesId
        )
        applyFocusRule(to: &newTodo)
        todos.append(newTodo)
        createTodoOnServer(newTodo)
        materializeRecurringOccurrences(from: newTodo)
    }

    func toggleComplete(_ todo: TodoEntry) {
        if let idx = todos.firstIndex(where: { $0.id == todo.id }) {
            if activeTimerTodoId == todo.id {
                stopTimer()
            }
            if todos[idx].status == .completed {
                todos[idx].status = .pending
                todos[idx].completedAt = nil
            } else {
                todos[idx].status = .completed
                todos[idx].completedAt = Date()
            }
            persistTodo(todos[idx])
            if todos[idx].status == .completed {
                ensureFutureOccurrence(after: todos[idx])
            }
        }
    }

    func deleteTodo(id: UUID) {
        if activeTimerTodoId == id {
            clearTimerState()
            clearStartUndo()
        }
        let removedTodo = todos.first { $0.id == id }
        todos.removeAll { $0.id == id }
        guard api.isAuthenticated else { return }

        api.deleteTodo(id: id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    if let removedTodo, self?.todos.contains(where: { $0.id == id }) == false {
                        self?.todos.append(removedTodo)
                    }
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { _ in }
            .store(in: &cancellables)
    }

    func finishTodo(id todoId: UUID) {
        if let idx = todos.firstIndex(where: { $0.id == todoId }) {
            if activeTimerTodoId == todoId {
                stopTimer()
            }
            todos[idx].status = .completed
            todos[idx].completedAt = Date()
            persistTodo(todos[idx])
            ensureFutureOccurrence(after: todos[idx])
        }
    }

    func updateTodo(_ todo: TodoEntry) {
        var updatedTodo = todo
        if updatedTodo.recurrenceFrequency != .none && updatedTodo.recurrenceSeriesId == nil {
            updatedTodo.recurrenceSeriesId = UUID()
        }
        applyFocusRule(to: &updatedTodo)
        let seriesAlreadyMaterialized = updatedTodo.recurrenceSeriesId.map { seriesId in
            todos.contains { $0.id != updatedTodo.id && $0.recurrenceSeriesId == seriesId }
        } ?? false
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index] = updatedTodo
        }
        persistTodo(updatedTodo)
        if !seriesAlreadyMaterialized {
            materializeRecurringOccurrences(from: updatedTodo)
        }
    }

    func addFocusBlock(_ block: FocusBlock) {
        focusBlocks.append(block)
        applyFocusRulesToScheduledTasks()
        saveActiveWorkspace()
    }

    func removeFocusBlock(id: UUID) {
        focusBlocks.removeAll { $0.id == id }
        saveActiveWorkspace()
    }


    // MARK: - Duplicate Todo
    func duplicateTodo(_ todo: TodoEntry) {

        let copy = TodoEntry(
            id: UUID(),
            title: "\(todo.title) (Copy)",
            description: todo.description,
            doDate: todo.doDate,
            dueDate: todo.dueDate,
            dueTime: todo.dueTime,
            descriptiveDeadline: todo.descriptiveDeadline,
            plannedStartTime: todo.plannedStartTime,
            plannedDuration: todo.plannedDuration,
            categoryId: todo.categoryId,
            status: .pending,
            priority: todo.priority,
            location: todo.location,
            reminder: todo.reminder,
            labels: todo.labels,
            timeSessions: nil,
            subtasks: (todo.subtasks ?? []).map { Subtask(id: UUID().uuidString, title: $0.title, isCompleted: false) },
            assigneeId: todo.assigneeId,
            recurrenceFrequency: .none
        )
        todos.append(copy)
        createTodoOnServer(copy)
    }

    // MARK: - Subtask Actions
    func addSubtask(to todoId: UUID, title: String) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let idx = todos.firstIndex(where: { $0.id == todoId }) {
            var subtasks = todos[idx].subtasks ?? []
            subtasks.append(Subtask(id: UUID().uuidString, title: title.trimmingCharacters(in: .whitespaces), isCompleted: false))
            todos[idx].subtasks = subtasks
            persistTodo(todos[idx])
        }
    }

    func toggleSubtask(todoId: UUID, subtaskId: String) {
        if let todoIdx = todos.firstIndex(where: { $0.id == todoId }),
           var subtasks = todos[todoIdx].subtasks,
           let subIdx = subtasks.firstIndex(where: { $0.id == subtaskId }) {
            subtasks[subIdx].isCompleted.toggle()
            todos[todoIdx].subtasks = subtasks
            persistTodo(todos[todoIdx])
        }
    }

    func deleteSubtask(todoId: UUID, subtaskId: String) {
        if let todoIdx = todos.firstIndex(where: { $0.id == todoId }),
           var subtasks = todos[todoIdx].subtasks {
            subtasks.removeAll { $0.id == subtaskId }
            todos[todoIdx].subtasks = subtasks
            persistTodo(todos[todoIdx])
        }
    }

    // MARK: - Recurrence & Live Schedule

    func pushOverdueTasks(at currentDate: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: currentDate)
        let currentMinutes = calendar.component(.hour, from: currentDate) * 60
            + calendar.component(.minute, from: currentDate)
        let roundedCurrentMinutes = max(7 * 60, Int(ceil(Double(currentMinutes) / 5.0) * 5.0))
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        // Anything left unfinished on an earlier scheduled day becomes an overdue
        // Today item. It is then included in the same ordered pass below, so every
        // following task is pushed after it rather than left overlapping it.
        for index in todos.indices where todos[index].status == .pending && todos[index].plannedStartTime != nil {
            let scheduledDay = calendar.startOfDay(for: todos[index].doDate)
            guard scheduledDay < today else { continue }
            if todos[index].overdueFromDate == nil {
                todos[index].overdueFromDate = scheduledDay
            }
            todos[index].doDate = today
            persistTodo(todos[index])
        }
        var overflowDate = tomorrow
        var overflowMinute = nextOpenMinute(on: overflowDate)

        let scheduledIndices = todos.indices
            .filter { index in
                let todo = todos[index]
                return calendar.isDate(todo.doDate, inSameDayAs: today)
                    && todo.status == .pending
                    && todo.id != activeTimerTodoId
                    && todo.plannedStartTime != nil
            }
            .sorted { lhs, rhs in
                (todos[lhs].plannedStartTime ?? "23:59") < (todos[rhs].plannedStartTime ?? "23:59")
            }

        var nextAvailableMinute = roundedCurrentMinutes

        for index in scheduledIndices {
            guard let time = todos[index].plannedStartTime else { continue }
            var plannedMinute = Self.minutes(from: time)
            let durationMinutes = min(15 * 60, max(5, Int(todos[index].plannedDuration / 60)))

            // Focus blocks reserve time for a category. Recurring tasks retain their
            // fixed slot; regular work is moved to the next allowed slot.
            if todos[index].recurrenceFrequency == .none {
                let allowed = nextAllowedSlot(for: todos[index], on: todos[index].doDate, from: plannedMinute)
                if !calendar.isDate(allowed.date, inSameDayAs: todos[index].doDate) {
                    todos[index].doDate = allowed.date
                    todos[index].plannedStartTime = Self.timeString(from: allowed.minute)
                    persistTodo(todos[index])
                    continue
                }
                plannedMinute = allowed.minute
                if plannedMinute != Self.minutes(from: time) { updatePushedTime(at: index, minute: plannedMinute) }
            }

            if plannedMinute >= nextAvailableMinute {
                nextAvailableMinute = plannedMinute + durationMinutes
                continue
            }

            if nextAvailableMinute + durationMinutes > 22 * 60 {
                if hasRecurringOccurrence(for: todos[index], on: tomorrow) {
                    let lastPossibleMinute = max(7 * 60, 22 * 60 - durationMinutes)
                    updatePushedTime(at: index, minute: lastPossibleMinute)
                    nextAvailableMinute = 22 * 60
                } else {
                    while overflowMinute + durationMinutes > 22 * 60 {
                        overflowDate = calendar.date(byAdding: .day, value: 1, to: overflowDate) ?? overflowDate
                        overflowMinute = nextOpenMinute(on: overflowDate)
                    }
                    if todos[index].originalPlannedStartTime == nil {
                        todos[index].originalPlannedStartTime = time
                    }
                    todos[index].doDate = overflowDate
                    todos[index].plannedStartTime = Self.timeString(from: overflowMinute)
                    overflowMinute += durationMinutes
                    persistTodo(todos[index])
                }
                continue
            }

            updatePushedTime(at: index, minute: nextAvailableMinute)
            nextAvailableMinute += durationMinutes
        }
    }

    private func updatePushedTime(at index: Int, minute: Int) {
        let oldTime = todos[index].plannedStartTime
        let newTime = Self.timeString(from: minute)
        guard oldTime != newTime else { return }
        if todos[index].originalPlannedStartTime == nil {
            todos[index].originalPlannedStartTime = oldTime
        }
        todos[index].plannedStartTime = newTime
        persistTodo(todos[index])
    }

    private func nextOpenMinute(on date: Date) -> Int {
        let scheduledEnds = todos.compactMap { todo -> Int? in
            guard Calendar.current.isDate(todo.doDate, inSameDayAs: date),
                  todo.status != .completed,
                  let time = todo.plannedStartTime else { return nil }
            return Self.minutes(from: time) + max(5, Int(todo.plannedDuration / 60))
        }
        return max(7 * 60, scheduledEnds.max() ?? 7 * 60)
    }

    private func applyFocusRulesToScheduledTasks() {
        for index in todos.indices {
            var todo = todos[index]
            guard applyFocusRule(to: &todo) else { continue }
            todos[index] = todo
            persistTodo(todo)
        }
    }

    @discardableResult
    private func applyFocusRule(to todo: inout TodoEntry) -> Bool {
        guard todo.status == .pending,
              todo.recurrenceFrequency == .none,
              let plannedStartTime = todo.plannedStartTime else { return false }

        let allowed = nextAllowedSlot(for: todo, on: todo.doDate, from: Self.minutes(from: plannedStartTime))
        guard !Calendar.current.isDate(allowed.date, inSameDayAs: todo.doDate)
                || allowed.minute != Self.minutes(from: plannedStartTime) else { return false }

        todo.doDate = allowed.date
        todo.plannedStartTime = Self.timeString(from: allowed.minute)
        return true
    }

    private func nextAllowedSlot(for todo: TodoEntry, on date: Date, from minute: Int) -> (date: Date, minute: Int) {
        let calendar = Calendar.current
        var candidateDate = calendar.startOfDay(for: date)
        var candidateMinute = max(7 * 60, minute)
        let durationMinutes = max(5, Int(todo.plannedDuration / 60))
        for _ in 0..<14 {
            let weekday = calendar.component(.weekday, from: candidateDate)
            let applicable = focusBlocks.filter { block in
                guard block.weekdays.contains(weekday) else { return false }
                // Older per-category blocks remain supported; new blocks express the
                // clearer rule that selected categories are allowed and all others move.
                if let categoryId = block.categoryId { return categoryId == todo.categoryId }
                return block.allowedCategoryIds.isEmpty || !block.allowedCategoryIds.contains(todo.categoryId ?? UUID())
            }

            while let block = applicable
                .filter({ candidateMinute < $0.endMinutes && candidateMinute + durationMinutes > $0.startMinutes })
                .max(by: { $0.endMinutes < $1.endMinutes }) {
                candidateMinute = block.endMinutes
            }
            if candidateMinute + durationMinutes <= 22 * 60 { return (candidateDate, candidateMinute) }
            candidateDate = calendar.date(byAdding: .day, value: 1, to: candidateDate) ?? candidateDate
            candidateMinute = 7 * 60
        }
        return (candidateDate, candidateMinute)
    }

    private func materializeRecurringOccurrences(from template: TodoEntry) {
        guard template.recurrenceFrequency != .none,
              let seriesId = template.recurrenceSeriesId else { return }

        let calendar = Calendar.current
        for occurrenceDate in recurrenceDates(after: template) {

            let alreadyExists = todos.contains {
                $0.recurrenceSeriesId == seriesId
                    && calendar.isDate($0.doDate, inSameDayAs: occurrenceDate)
            }
            guard !alreadyExists else { continue }

            let dueDateOffset = template.dueDate.map {
                calendar.dateComponents([.day], from: calendar.startOfDay(for: template.doDate), to: calendar.startOfDay(for: $0)).day ?? 0
            }
            let occurrenceDueDate = dueDateOffset.flatMap {
                calendar.date(byAdding: .day, value: $0, to: occurrenceDate)
            }

            let occurrence = TodoEntry(
                id: UUID(),
                title: template.title,
                description: template.description,
                doDate: occurrenceDate,
                dueDate: occurrenceDueDate,
                dueTime: template.dueTime,
                descriptiveDeadline: template.descriptiveDeadline,
                plannedStartTime: template.plannedStartTime,
                plannedDuration: template.plannedDuration,
                categoryId: template.categoryId,
                status: .pending,
                priority: template.priority,
                location: template.location,
                reminder: template.reminder,
                labels: template.labels,
                timeSessions: nil,
                subtasks: (template.subtasks ?? []).map {
                    Subtask(id: UUID().uuidString, title: $0.title, isCompleted: false)
                },
                assigneeId: template.assigneeId,
                recurrenceFrequency: template.recurrenceFrequency,
                recurrenceWeekdays: template.recurrenceWeekdays,
                recurrenceSeriesId: seriesId
            )
            todos.append(occurrence)
            createTodoOnServer(occurrence)
        }
    }

    private func ensureFutureOccurrence(after todo: TodoEntry) {
        guard todo.recurrenceFrequency != .none,
              let seriesId = todo.recurrenceSeriesId else { return }
        let calendar = Calendar.current
        guard let nextDate = recurrenceDates(after: todo).first else { return }
        guard !todos.contains(where: {
            $0.recurrenceSeriesId == seriesId && calendar.isDate($0.doDate, inSameDayAs: nextDate)
        }) else { return }
        materializeRecurringOccurrences(from: todo)
    }

    private func recurrenceDates(after template: TodoEntry) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: template.doDate)

        switch template.recurrenceFrequency {
        case .none:
            return []
        case .daily:
            return (1...14).compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
        case .weekly:
            return (1...8).compactMap {
                calendar.date(byAdding: .weekOfYear, value: $0, to: start)
            }
        case .monthly:
            return (1...6).compactMap {
                calendar.date(byAdding: .month, value: $0, to: start)
            }
        case .custom:
            var weekdays = Set(template.recurrenceWeekdays ?? [])
                .filter { (1...7).contains($0) }
            if weekdays.isEmpty {
                weekdays.insert(calendar.component(.weekday, from: start))
            }
            return (1...(8 * 7)).compactMap { offset -> Date? in
                guard let date = calendar.date(byAdding: .day, value: offset, to: start),
                      weekdays.contains(calendar.component(.weekday, from: date)) else {
                    return nil
                }
                return date
            }
        }
    }

    private func applyTravelTimes(_ travelTimes: [APIClient.TravelTimeResponse]?) {
        guard let travelTimes else { return }
        locationTravelTimes = travelTimes.reduce(into: [:]) { result, item in
            result[item.locationKey] = item.durationMinutes
        }
    }

    private func hasRecurringOccurrence(for todo: TodoEntry, on date: Date) -> Bool {
        guard todo.recurrenceFrequency != .none,
              let seriesId = todo.recurrenceSeriesId else { return false }
        return todos.contains {
            $0.id != todo.id
                && $0.recurrenceSeriesId == seriesId
                && Calendar.current.isDate($0.doDate, inSameDayAs: date)
        }
    }

    private static func minutes(from time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 9 * 60 }
        return parts[0] * 60 + parts[1]
    }

    private static func timeString(from minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private static func roundedUpToFiveMinutes(_ date: Date) -> Int {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return Int(ceil(Double(minutes) / 5.0) * 5.0)
    }

    private func createTodoOnServer(_ todo: TodoEntry) {
        guard api.isAuthenticated else { return }

        api.createTodo(todo)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] createdTodo in
                guard let self,
                      let index = self.todos.firstIndex(where: { $0.id == todo.id }) else { return }
                var mergedTodo = createdTodo
                mergedTodo.timeSessions = self.todos[index].timeSessions
                self.todos[index] = mergedTodo
            }
            .store(in: &cancellables)
    }

    private func persistSessionStart(_ session: TimeSession) {
        guard api.isAuthenticated, let todoId = session.todoId else { return }
        api.createTimeSession(todoId: todoId, start: session.start)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] savedSession in
                guard let self else { return }
                self.serverSessionIds[session.id] = savedSession.id
                if self.cancelledSessionIds.contains(session.id) {
                    self.deleteServerSession(id: savedSession.id)
                    return
                }
                if let todoIndex = self.todos.firstIndex(where: { $0.id == todoId }),
                   let localSession = self.todos[todoIndex].timeSessions?.first(where: { $0.id == session.id }),
                   localSession.end != nil {
                    self.persistSessionEnd(localSession)
                }
            }
            .store(in: &cancellables)
    }

    private func persistSessionEnd(_ session: TimeSession) {
        guard api.isAuthenticated,
              let end = session.end,
              let serverId = serverSessionIds[session.id] else { return }
        api.finishTimeSession(id: serverId, end: end)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { _ in }
            .store(in: &cancellables)
    }

    private func cancelSession(id localId: UUID) {
        cancelledSessionIds.insert(localId)
        if let serverId = serverSessionIds[localId] {
            deleteServerSession(id: serverId)
        }
    }

    private func deleteServerSession(id: UUID) {
        guard api.isAuthenticated else { return }
        api.deleteTimeSession(id: id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { _ in }
            .store(in: &cancellables)
    }

    private func persistTodo(_ todo: TodoEntry) {
        guard api.isAuthenticated else { return }

        let mutationVersion = (todoMutationVersions[todo.id] ?? 0) + 1
        todoMutationVersions[todo.id] = mutationVersion

        api.updateTodo(todo)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] savedTodo in
                guard let self,
                      self.todoMutationVersions[savedTodo.id] == mutationVersion,
                      let index = self.todos.firstIndex(where: { $0.id == savedTodo.id }) else { return }
                var mergedTodo = savedTodo
                mergedTodo.timeSessions = self.todos[index].timeSessions
                self.todos[index] = mergedTodo
            }
            .store(in: &cancellables)
    }

    func addCategory(name: String, colorHex: String, icon: String) {
        let cat = Category(id: UUID(), name: name, colorHex: colorHex, icon: icon, notes: "# \(icon) \(name) Document\n\nType notes...")
        categories.append(cat)
        guard api.isAuthenticated else { return }

        api.createCategory(cat)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] createdCategory in
                guard let self,
                      let index = self.categories.firstIndex(where: { $0.id == cat.id }) else { return }
                self.categories[index] = createdCategory
                for todoIndex in self.todos.indices where self.todos[todoIndex].categoryId == cat.id {
                    self.todos[todoIndex].categoryId = createdCategory.id
                }
            }
            .store(in: &cancellables)
    }

    func updateCategory(_ category: Category) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index] = category
        guard api.isAuthenticated else { return }

        api.updateCategory(category)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] updatedCategory in
                guard let self,
                      let catIndex = self.categories.firstIndex(where: { $0.id == updatedCategory.id }) else { return }
                self.categories[catIndex] = updatedCategory
            }
            .store(in: &cancellables)
    }

    func deleteCategory(id: UUID) {
        guard let removedCategory = categories.first(where: { $0.id == id }) else { return }
        let previousTodos = todos
        categories.removeAll { $0.id == id }
        for index in todos.indices where todos[index].categoryId == id {
            todos[index].categoryId = nil
        }
        guard api.isAuthenticated else { return }

        api.deleteCategory(id: id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.categories.append(removedCategory)
                    self?.todos = previousTodos
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { _ in }
            .store(in: &cancellables)
    }
}
