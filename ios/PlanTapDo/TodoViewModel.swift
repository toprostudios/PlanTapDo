// TodoViewModel.swift
import Foundation
import Combine
import SwiftUI

enum DisplayStyle: String, CaseIterable {
    case list = "List"
    case calendar = "Calendar"
}

class TodoViewModel: ObservableObject {
    @Published var userAccount: UserAccount
    @Published var availableAccounts: [UserAccount] = []
    @Published var todos: [TodoEntry] = []
    @Published var categories: [Category] = []
    @Published var locationTravelTimes: [String: Int] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    // UI State
    @Published var selectedTab: Int = 0 // 0: Today, 1: Future, 2: Categories, 3: Settings
    @Published var displayStyle: DisplayStyle = .list
    @Published var selectedFutureDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @Published var currentWeekOffset: Int = 0
    @Published var theme: AppTheme = .dark

    // MARK: - Timer State
    @Published var activeTimerTodoId: UUID? = nil
    @Published var timerSecondsElapsed: Int = 0
    private var timer: Timer? = nil

    var timerFormatted: String {
        let mins = timerSecondsElapsed / 60
        let secs = timerSecondsElapsed % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    func startTimer(for todo: TodoEntry) {
        stopTimer()
        activeTimerTodoId = todo.id
        if let idx = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[idx].status = .inProgress
            persistTodo(todos[idx])
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
            persistTodo(todos[idx])
        }
        clearTimerState()
    }

    private func clearTimerState() {
        timer?.invalidate()
        timer = nil
        activeTimerTodoId = nil
        timerSecondsElapsed = 0
    }


    private var cancellables = Set<AnyCancellable>()
    private let api = APIClient.shared
    private var accountTokens: [UUID: String] = [:]

    init() {
        let personalAccount = UserAccount(
            id: UUID(),
            name: "Personal Account",
            email: "personal@plantapdo.app",
            tier: "Demo",
            isCloudSynced: false
        )

        self.userAccount = personalAccount
        self.availableAccounts = [personalAccount]

        loadSampleData()
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
        locationTravelTimes[key] = durationMinutes
    }

    func switchAccount(_ account: UserAccount) {
        clearTimerState()
        userAccount = account
        if let token = accountTokens[account.id] {
            api.setAuthToken(token)
            fetchTodos()
        } else {
            api.clearAuthToken()
            loadSampleData()
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
                self.api.setAuthToken(response.tokens.access)
                let account = UserAccount(
                    id: response.id,
                    name: response.username,
                    email: response.email,
                    tier: "Cloud",
                    isCloudSynced: true
                )
                self.availableAccounts.removeAll { $0.id == account.id }
                self.availableAccounts.append(account)
                self.accountTokens[account.id] = response.tokens.access
                self.userAccount = account
                self.fetchTodos()
            }
            .store(in: &cancellables)
    }

    // MARK: - Sample Data Setup
    func loadSampleData() {
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
                status: .inProgress,
                priority: .high,
                location: "HQ Office (3rd Floor)",
                reminder: "15 minutes before",
                labels: ["product", "roadmap"],
                timeSessions: nil,
                subtasks: [
                    Subtask(id: UUID().uuidString, title: "Check sprint backlog estimates", isCompleted: true),
                    Subtask(id: UUID().uuidString, title: "Verify design mockup deliverables", isCompleted: false),
                    Subtask(id: UUID().uuidString, title: "Draft release timeline email", isCompleted: false)
                ],
                assigneeId: nil
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
                timeSessions: nil,
                subtasks: [
                    Subtask(id: UUID().uuidString, title: "Stretching & warm up", isCompleted: true),
                    Subtask(id: UUID().uuidString, title: "30m strength workout", isCompleted: true)
                ],
                assigneeId: nil
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
                assigneeId: nil
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
                assigneeId: nil
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
                assigneeId: nil
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
                assigneeId: nil
            )
        ]
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
                self?.todos = state.todos
                self?.categories = state.categories
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
        priority: PriorityLevel? = .medium,
        location: String? = nil,
        reminder: String? = nil,
        labels: [String]? = nil
    ) {
        let newTodo = TodoEntry(
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
            assigneeId: nil
        )
        todos.append(newTodo)
        createTodoOnServer(newTodo)
    }

    func toggleComplete(_ todo: TodoEntry) {
        if let idx = todos.firstIndex(where: { $0.id == todo.id }) {
            if activeTimerTodoId == todo.id {
                clearTimerState()
            }
            todos[idx].status = (todos[idx].status == .completed) ? .pending : .completed
            persistTodo(todos[idx])
        }
    }

    func deleteTodo(id: UUID) {
        if activeTimerTodoId == id {
            clearTimerState()
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
                clearTimerState()
            }
            todos[idx].status = .completed
            persistTodo(todos[idx])
        }
    }

    func updateTodo(_ todo: TodoEntry) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index] = todo
        }
        persistTodo(todo)
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
            assigneeId: todo.assigneeId
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
                self.todos[index] = createdTodo
            }
            .store(in: &cancellables)
    }

    private func persistTodo(_ todo: TodoEntry) {
        guard api.isAuthenticated else { return }

        api.updateTodo(todo)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] savedTodo in
                guard let index = self?.todos.firstIndex(where: { $0.id == savedTodo.id }) else { return }
                self?.todos[index] = savedTodo
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

    func deleteCategory(id: UUID) {
        let removedCategory = categories.first { $0.id == id }
        let removedTodos = todos.filter { $0.categoryId == id }
        categories.removeAll { $0.id == id }
        todos.removeAll { $0.categoryId == id }
        guard api.isAuthenticated else { return }

        api.deleteCategory(id: id)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    if let removedCategory {
                        self?.categories.append(removedCategory)
                    }
                    self?.todos.append(contentsOf: removedTodos)
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { _ in }
            .store(in: &cancellables)
    }
}
