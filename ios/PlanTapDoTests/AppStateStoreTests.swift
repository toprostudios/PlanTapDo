import XCTest
@testable import PlanTapDo

final class AppStateStoreTests: XCTestCase {
    private func makeViewModel() -> (TodoViewModel, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = AppStateStore(fileURL: directory.appendingPathComponent("app-state.json"))
        return (TodoViewModel(stateStore: store), directory)
    }

    func testRoundTripPreservesWorkspaceAndTimerSessions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("app-state.json")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let account = UserAccount(
            id: UUID(),
            name: "Personal Account",
            email: "personal@plantapdo.app",
            tier: "Personal",
            isCloudSynced: false
        )
        let todoID = UUID()
        let session = TimeSession(
            id: UUID(),
            todoId: todoID,
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_000_600),
            duration: 600
        )
        let todo = TodoEntry(
            id: todoID,
            title: "Persist this task",
            description: "Local data survives relaunch",
            doDate: Date(timeIntervalSince1970: 1_700_000_000),
            dueDate: nil,
            dueTime: nil,
            descriptiveDeadline: nil,
            plannedStartTime: "09:00",
            plannedDuration: 1_800,
            categoryId: nil,
            status: .inProgress,
            priority: .high,
            location: nil,
            reminder: nil,
            labels: ["test"],
            timeSessions: [session],
            subtasks: [],
            assigneeId: nil
        )
        let state = PersistedAppState(
            accounts: [account],
            activeAccountID: account.id,
            workspaces: [
                account.id: WorkspaceState(
                    todos: [todo],
                    categories: [],
                    locationTravelTimes: [:],
                    focusBlocks: []
                )
            ]
        )
        let store = AppStateStore(fileURL: fileURL)

        try store.save(state)
        let restored = try XCTUnwrap(store.load())

        XCTAssertEqual(restored.activeAccountID, account.id)
        let restoredTodo = try XCTUnwrap(restored.workspaces[account.id]?.todos.first)
        XCTAssertEqual(restoredTodo.title, todo.title)
        XCTAssertEqual(restoredTodo.plannedDuration, todo.plannedDuration)
        XCTAssertEqual(restoredTodo.timeSessions, [session])
    }

    func testAuthTokensCanBeEncodedForKeychainStorage() throws {
        let tokens = APIClient.AuthTokens(access: "access", refresh: "refresh")
        let data = try JSONEncoder().encode(tokens)
        XCTAssertEqual(try JSONDecoder().decode(APIClient.AuthTokens.self, from: data), tokens)
    }

    func testNewScheduleDoesNotCreatePlannedHistory() throws {
        let todo = TodoEntry(
            id: UUID(),
            title: "Scheduled task",
            description: nil,
            doDate: Date(),
            dueDate: nil,
            dueTime: nil,
            descriptiveDeadline: nil,
            plannedStartTime: "09:00",
            plannedDuration: 1_800,
            categoryId: nil,
            status: .pending,
            priority: nil,
            location: nil,
            reminder: nil,
            labels: nil,
            timeSessions: nil,
            subtasks: nil,
            assigneeId: nil
        )

        XCTAssertNil(todo.originalPlannedStartTime)

        let encoded = try JSONEncoder().encode(todo)
        let decoded = try JSONDecoder().decode(TodoEntry.self, from: encoded)
        XCTAssertNil(decoded.originalPlannedStartTime)
    }

    func testServerValidationErrorsAreReadable() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "password": ["This password is too short.", "This password is too common."],
            "username": ["This field is required."],
        ])

        let message = APIClient.serverMessage(from: data, statusCode: 400)

        XCTAssertTrue(message.contains("Password: This password is too short."))
        XCTAssertTrue(message.contains("This password is too common."))
        XCTAssertTrue(message.contains("Username: This field is required."))
    }

    func testSyncedCalendarDateStaysOnTheSameLocalDay() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))
        let date = try XCTUnwrap(TodoEntry.apiDate(from: "2026-08-14", in: timeZone))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 14)
    }

    func testCustomRecurrenceUsesSelectedWeekdays() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let start = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 17))
        )

        viewModel.createTodo(
            title: "Monday and Thursday",
            doDate: start,
            recurrenceFrequency: .custom,
            recurrenceWeekdays: [2, 5]
        )

        let dates = viewModel.todos.dropFirst().map(\.doDate)
        XCTAssertEqual(dates.count, 16)
        XCTAssertTrue(dates.allSatisfy {
            [2, 5].contains(Calendar.current.component(.weekday, from: $0))
        })
        XCTAssertEqual(
            Set(dates.map { Calendar.current.component(.weekday, from: $0) }),
            Set([2, 5])
        )
    }

    func testMonthlyRecurrenceAdvancesByCalendarMonth() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let start = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15))
        )

        viewModel.createTodo(
            title: "Monthly review",
            doDate: start,
            recurrenceFrequency: .monthly
        )

        let monthValues = viewModel.todos.dropFirst().map {
            Calendar.current.component(.month, from: $0.doDate)
        }
        XCTAssertEqual(monthValues, [2, 3, 4, 5, 6, 7])
    }

    func testSwitchingToCloudAccountRestoresOnlyItsCachedWorkspace() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = AppStateStore(fileURL: directory.appendingPathComponent("app-state.json"))
        let local = UserAccount(
            id: UUID(),
            name: "Local",
            email: "local@example.com",
            tier: "Personal",
            isCloudSynced: false
        )
        let cloud = UserAccount(
            id: UUID(),
            name: "Cloud",
            email: "cloud@example.com",
            tier: "Cloud",
            isCloudSynced: true
        )
        let localTodo = makeTodo(title: "Local only")
        let cloudTodo = makeTodo(title: "Cloud only")
        try store.save(
            PersistedAppState(
                accounts: [local, cloud],
                activeAccountID: local.id,
                workspaces: [
                    local.id: WorkspaceState(
                        todos: [localTodo], categories: [], locationTravelTimes: [:], focusBlocks: []
                    ),
                    cloud.id: WorkspaceState(
                        todos: [cloudTodo], categories: [], locationTravelTimes: [:], focusBlocks: []
                    ),
                ]
            )
        )
        let viewModel = TodoViewModel(stateStore: store)

        viewModel.switchAccount(cloud)

        XCTAssertEqual(viewModel.todos.map(\.title), ["Cloud only"])
        XCTAssertEqual(viewModel.errorMessage, "Sign in again to resume cloud sync.")
    }

    func testDeletingCategoryUnassignsCategoryFromTasksWithoutDeletingTasks() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        viewModel.addCategory(name: "Work", colorHex: "7C6FF7", icon: "💼")
        let category = try XCTUnwrap(viewModel.categories.first)

        viewModel.createTodo(
            title: "Important work item",
            categoryId: category.id
        )

        XCTAssertEqual(viewModel.todos.count, 1)
        XCTAssertEqual(viewModel.todos.first?.categoryId, category.id)

        viewModel.deleteCategory(id: category.id)

        XCTAssertTrue(viewModel.categories.isEmpty)
        XCTAssertEqual(viewModel.todos.count, 1)
        XCTAssertEqual(viewModel.todos.first?.title, "Important work item")
        XCTAssertNil(viewModel.todos.first?.categoryId)
    }

    func testWorkspaceStateSafelyHandlesDuplicateTodoIDsDuringEncoding() throws {
        let todoID = UUID()
        let todo1 = makeTodo(title: "Task 1")
        var todo2 = makeTodo(title: "Task 2")
        // Same ID simulating sync collision
        let mirrorTodo = TodoEntry(
            id: todo1.id,
            title: "Task 1 Duplicate",
            description: nil,
            doDate: Date(),
            dueDate: nil,
            dueTime: nil,
            descriptiveDeadline: nil,
            plannedStartTime: nil,
            plannedDuration: 1800,
            categoryId: nil,
            status: .pending,
            priority: nil,
            location: nil,
            reminder: nil,
            labels: nil,
            timeSessions: [],
            subtasks: nil,
            assigneeId: nil
        )

        let state = WorkspaceState(
            todos: [todo1, mirrorTodo],
            categories: [],
            locationTravelTimes: [:],
            focusBlocks: []
        )

        XCTAssertNoThrow(try JSONEncoder().encode(state))
    }

    private func makeTodo(title: String) -> TodoEntry {
        TodoEntry(
            id: UUID(),
            title: title,
            description: nil,
            doDate: Date(),
            dueDate: nil,
            dueTime: nil,
            descriptiveDeadline: nil,
            plannedStartTime: nil,
            plannedDuration: 1_800,
            categoryId: nil,
            status: .pending,
            priority: nil,
            location: nil,
            reminder: nil,
            labels: nil,
            timeSessions: nil,
            subtasks: nil,
            assigneeId: nil
        )
    }
}
