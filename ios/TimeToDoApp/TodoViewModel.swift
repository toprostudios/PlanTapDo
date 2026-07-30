// TodoViewModel.swift
import Foundation
import Combine
import SwiftUI

enum DisplayStyle: String, CaseIterable {
    case list = "List"
    case calendar = "Calendar"
    case kanban = "Kanban"
}

class TodoViewModel: ObservableObject {
    @Published var userAccount: UserAccount
    @Published var availableAccounts: [UserAccount] = []
    @Published var teamMembers: [TeamMember] = []
    @Published var todos: [TodoEntry] = []
    @Published var categories: [Category] = []
    @Published var locationTravelTimes: [String: Int] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    // UI State
    @Published var selectedTab: Int = 0 // 0: Today, 1: Future, 2: Categories, 3: Team
    @Published var displayStyle: DisplayStyle = .list
    @Published var selectedFutureDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @Published var currentWeekOffset: Int = 0
    @Published var theme: AppTheme = .dark
    @Published var showingSettings: Bool = false
    @Published var showingAccountModal: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let api = APIClient.shared

    init() {
        let acc1 = UserAccount(id: UUID(), name: "Tony Pro Workspace", email: "tony@plantapdo.app", tier: "Pro", isCloudSynced: true)
        let acc2 = UserAccount(id: UUID(), name: "Personal Account", email: "tony.personal@plantapdo.app", tier: "Free", isCloudSynced: true)
        let acc3 = UserAccount(id: UUID(), name: "Product Team Workspace", email: "team@plantapdo.app", tier: "Enterprise", isCloudSynced: true)

        self.userAccount = acc1
        self.availableAccounts = [acc1, acc2, acc3]

        let tm1 = TeamMember(id: UUID(), name: "Alex Vance", role: "Lead UI/UX Designer 🎨", department: "Design", status: "active", capacityMinutes: 360)
        let tm2 = TeamMember(id: UUID(), name: "Sarah Chen", role: "Senior Frontend Architect 💻", department: "Engineering", status: "active", capacityMinutes: 480)
        let tm3 = TeamMember(id: UUID(), name: "Marcus Brody", role: "Group Product Manager 📊", department: "Product", status: "active", capacityMinutes: 300)
        let tm4 = TeamMember(id: UUID(), name: "Elena Rostova", role: "DevOps Lead ⚙️", department: "Infrastructure", status: "break", capacityMinutes: 240)

        self.teamMembers = [tm1, tm2, tm3, tm4]

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
        self.userAccount = account
    }

    func createAndSwitchAccount(name: String, email: String) {
        guard !name.isEmpty && !email.isEmpty else { return }
        let newAcc = UserAccount(id: UUID(), name: name, email: email, tier: "Pro", isCloudSynced: true)
        availableAccounts.append(newAcc)
        userAccount = newAcc
    }

    // MARK: - Sample Data Setup
    func loadSampleData() {
        let catWork = Category(id: UUID(), name: "Work & Projects", colorHex: "7C6FF7", icon: "💼", notes: "# 💼 Work & Projects Notion Canvas\n\n- [ ] Review sprint specs\n- [ ] Ship Kanban views")
        let catPersonal = Category(id: UUID(), name: "Personal & Life", colorHex: "3ECF8E", icon: "🏡", notes: "# 🏡 Personal & Life Document\n\n- [ ] Buy groceries\n- [ ] Family call")
        let catHealth = Category(id: UUID(), name: "Health & Fitness", colorHex: "F5A623", icon: "🏋️", notes: "# 🏋️ Health Log\n\n- Workout schedule")
        let catLearning = Category(id: UUID(), name: "Learning & Skills", colorHex: "60A5FA", icon: "📚", notes: "# 📚 Learning Notebook\n\n- Read Clean Architecture")

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
                    Subtask(id: UUID(), title: "Check sprint backlog estimates", isCompleted: true),
                    Subtask(id: UUID(), title: "Verify design mockup deliverables", isCompleted: false),
                    Subtask(id: UUID(), title: "Draft release timeline email", isCompleted: false)
                ],
                assigneeId: teamMembers.first?.id
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
                    Subtask(id: UUID(), title: "Stretching & warm up", isCompleted: true),
                    Subtask(id: UUID(), title: "30m strength workout", isCompleted: true)
                ],
                assigneeId: teamMembers.first?.id
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
                    Subtask(id: UUID(), title: "Audit high-contrast tokens", isCompleted: false),
                    Subtask(id: UUID(), title: "Test 3-day and weekly view modes", isCompleted: false)
                ],
                assigneeId: teamMembers.count > 1 ? teamMembers[1].id : nil
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
                assigneeId: teamMembers.count > 1 ? teamMembers[1].id : nil
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
                assigneeId: teamMembers.first?.id
            ),
            TodoEntry(
                id: UUID(),
                title: "Sprint Retrospective & Team Sync",
                description: "Discuss wins, blockers, and process improvements for next sprint.",
                doDate: nextWeek,
                dueDate: nextWeek,
                dueTime: "15:00",
                descriptiveDeadline: "Before sprint end",
                plannedStartTime: "14:00",
                plannedDuration: 3600,
                categoryId: catWork.id,
                status: .pending,
                priority: .high,
                location: "HQ Office (3rd Floor)",
                reminder: "15 minutes before",
                labels: ["sprint", "retro"],
                timeSessions: nil,
                subtasks: [],
                assigneeId: teamMembers.count > 3 ? teamMembers[3].id : nil
            )
        ]
    }

    // MARK: - Fetch
    func fetchTodos() {
        isLoading = true
        api.fetchTodos()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure = completion {
                    // Retain local sample data on failure
                }
            } receiveValue: { [weak self] fetched in
                if !fetched.isEmpty {
                    self?.todos = fetched
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions
    func createTodo(
        title: String,
        description: String?,
        doDate: Date,
        dueDate: Date?,
        dueTime: String?,
        descriptiveDeadline: String?,
        plannedStartTime: String?,
        plannedDuration: TimeInterval,
        categoryId: UUID?,
        priority: PriorityLevel?,
        location: String?,
        reminder: String?,
        labels: [String]?
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
            assigneeId: teamMembers.first?.id
        )
        todos.append(newTodo)
    }

    func toggleComplete(_ todo: TodoEntry) {
        if let idx = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[idx].status = (todos[idx].status == .completed) ? .pending : .completed
        }
    }

    func deleteTodo(id: UUID) {
        todos.removeAll { $0.id == id }
    }

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
            subtasks: (todo.subtasks ?? []).map { Subtask(id: UUID(), title: $0.title, isCompleted: false) },
            assigneeId: todo.assigneeId
        )
        todos.append(copy)
    }

    // MARK: - Subtask Actions
    func addSubtask(to todoId: UUID, title: String) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let idx = todos.firstIndex(where: { $0.id == todoId }) {
            var subtasks = todos[idx].subtasks ?? []
            subtasks.append(Subtask(id: UUID(), title: title.trimmingCharacters(in: .whitespaces), isCompleted: false))
            todos[idx].subtasks = subtasks
        }
    }

    func toggleSubtask(todoId: UUID, subtaskId: UUID) {
        if let todoIdx = todos.firstIndex(where: { $0.id == todoId }),
           var subtasks = todos[todoIdx].subtasks,
           let subIdx = subtasks.firstIndex(where: { $0.id == subtaskId }) {
            subtasks[subIdx].isCompleted.toggle()
            todos[todoIdx].subtasks = subtasks
        }
    }

    func deleteSubtask(todoId: UUID, subtaskId: UUID) {
        if let todoIdx = todos.firstIndex(where: { $0.id == todoId }),
           var subtasks = todos[todoIdx].subtasks {
            subtasks.removeAll { $0.id == subtaskId }
            todos[todoIdx].subtasks = subtasks
        }
    }

    func addCategory(name: String, colorHex: String, icon: String) {
        let cat = Category(id: UUID(), name: name, colorHex: colorHex, icon: icon, notes: "# \(icon) \(name) Document\n\nType notes...")
        categories.append(cat)
    }

    func deleteCategory(id: UUID) {
        categories.removeAll { $0.id == id }
        todos.removeAll { $0.categoryId == id }
    }
}
