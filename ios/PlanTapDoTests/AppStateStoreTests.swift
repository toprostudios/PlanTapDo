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
        let directoryValues = try directory.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(directoryValues.isExcludedFromBackup, true)
    }

    func testAuthTokensCanBeEncodedForKeychainStorage() throws {
        let tokens = APIClient.AuthTokens(access: "access", refresh: "refresh")
        let data = try JSONEncoder().encode(tokens)
        XCTAssertEqual(try JSONDecoder().decode(APIClient.AuthTokens.self, from: data), tokens)
    }

    func testTaskEncodingDoesNotContainLegacyCalendarGhostFields() throws {
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

        let encoded = try JSONEncoder().encode(todo)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertNil(object["originalPlannedStartTime"])
        XCTAssertNil(object["overdueFromDate"])
    }

    func testLegacyWorkspaceWithoutNewSectionsStillDecodes() throws {
        let data = try XCTUnwrap(
            """
            {"todos":[],"categories":[]}
            """.data(using: .utf8)
        )

        let workspace = try JSONDecoder().decode(WorkspaceState.self, from: data)

        XCTAssertTrue(workspace.todos.isEmpty)
        XCTAssertTrue(workspace.categories.isEmpty)
        XCTAssertTrue(workspace.locationTravelTimes.isEmpty)
        XCTAssertTrue(workspace.focusBlocks.isEmpty)
        XCTAssertFalse(workspace.needsCloudSync)
        XCTAssertTrue(workspace.deletedTodoIDs.isEmpty)
    }

    func testStartingScheduledTaskCreatesOnlyActualSessionHistory() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        viewModel.createTodo(title: "Planned work", plannedStartTime: "09:00")
        let todo = try XCTUnwrap(viewModel.todos.first)

        viewModel.startTimer(for: todo)
        addTeardownBlock { viewModel.undoLastStart() }

        XCTAssertEqual(viewModel.todos.first?.status, .inProgress)
        XCTAssertEqual(viewModel.todos.first?.timeSessions?.count, 1)
        XCTAssertNotNil(viewModel.todos.first?.timeSessions?.first?.start)
    }

    func testStartingUnscheduledTaskSchedulesItAtItsActualStart() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        viewModel.createTodo(title: "Unplanned work")
        let todo = try XCTUnwrap(viewModel.todos.first)

        viewModel.startTimer(for: todo)
        addTeardownBlock { viewModel.undoLastStart() }

        XCTAssertNotNil(viewModel.todos.first?.plannedStartTime)
        XCTAssertEqual(viewModel.todos.first?.timeSessions?.count, 1)
    }

    func testFreeAccountsAreLimitedToTwoCategories() {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNotNil(viewModel.addCategory(name: "One", colorHex: "7C6FF7", icon: "1", isPremium: false))
        XCTAssertNotNil(viewModel.addCategory(name: "Two", colorHex: "3ECF8E", icon: "2", isPremium: false))
        XCTAssertNil(viewModel.addCategory(name: "Three", colorHex: "F5A623", icon: "3", isPremium: false))
        XCTAssertEqual(viewModel.categories.count, TodoViewModel.freeCategoryLimit)
        XCTAssertNotNil(viewModel.addCategory(name: "Premium", colorHex: "60A5FA", icon: "4", isPremium: true))
    }

    func testStartingTaskThatIsNotInWorkspaceDoesNotCreateOrphanTimer() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        viewModel.createTodo(title: "Already deleted")
        let missingTodo = try XCTUnwrap(viewModel.todos.first)
        viewModel.deleteTodo(id: missingTodo.id)

        viewModel.startTimer(for: missingTodo)

        XCTAssertNil(viewModel.activeTimerTodoId)
        let noTick = expectation(description: "No orphan ticker fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            XCTAssertEqual(viewModel.timerSecondsElapsed, 0)
            noTick.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    func testOverdueTasksOverflowAcrossDaysWithoutColliding() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 21, minute: 50))
        )
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))

        viewModel.createTodo(
            title: "Existing tomorrow",
            doDate: tomorrow,
            plannedStartTime: "07:00",
            plannedDuration: 3_600
        )
        viewModel.createTodo(
            title: "First pushed",
            doDate: now,
            plannedStartTime: "20:00",
            plannedDuration: 1_800
        )
        viewModel.createTodo(
            title: "Second pushed",
            doDate: now,
            plannedStartTime: "20:30",
            plannedDuration: 1_800
        )

        viewModel.pushOverdueTasks(at: now)

        let first = try XCTUnwrap(viewModel.todos.first { $0.title == "First pushed" })
        let second = try XCTUnwrap(viewModel.todos.first { $0.title == "Second pushed" })
        XCTAssertTrue(calendar.isDate(first.doDate, inSameDayAs: tomorrow))
        XCTAssertTrue(calendar.isDate(second.doDate, inSameDayAs: tomorrow))
        XCTAssertEqual(first.plannedStartTime, "08:00")
        XCTAssertEqual(second.plannedStartTime, "08:30")
    }

    func testCalendarOverlapLayoutUsesStableLanesForTransitiveCluster() {
        let first = makeTodo(
            title: "First",
            plannedStartTime: "09:00",
            plannedDuration: 3_600
        )
        let middle = makeTodo(
            title: "Middle",
            plannedStartTime: "09:30",
            plannedDuration: 3_600
        )
        let last = makeTodo(
            title: "Last",
            plannedStartTime: "10:00",
            plannedDuration: 3_600
        )

        let layout = CalendarOverlapLayout.compute(for: [first, middle, last])

        XCTAssertEqual(layout[first.id]?.totalCols, 2)
        XCTAssertEqual(layout[middle.id]?.totalCols, 2)
        XCTAssertEqual(layout[last.id]?.totalCols, 2)
        XCTAssertEqual(layout[first.id]?.colIndex, layout[last.id]?.colIndex)
        XCTAssertNotEqual(layout[first.id]?.colIndex, layout[middle.id]?.colIndex)
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
        let todo1 = makeTodo(title: "Task 1")
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

    private func makeTodo(
        title: String,
        plannedStartTime: String? = nil,
        plannedDuration: TimeInterval = 1_800
    ) -> TodoEntry {
        TodoEntry(
            id: UUID(),
            title: title,
            description: nil,
            doDate: Date(),
            dueDate: nil,
            dueTime: nil,
            descriptiveDeadline: nil,
            plannedStartTime: plannedStartTime,
            plannedDuration: plannedDuration,
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
