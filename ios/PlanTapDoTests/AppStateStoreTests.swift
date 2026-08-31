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

    func testStateStoreRecoversFromBackupWhenPrimaryFileIsDamaged() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("app-state.json")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let account = UserAccount(
            id: UUID(),
            name: "Recovered",
            email: "local@plantapdo.app",
            tier: "Personal",
            isCloudSynced: false
        )
        let expected = PersistedAppState(
            accounts: [account],
            activeAccountID: account.id,
            workspaces: [account.id: .empty]
        )
        let store = AppStateStore(fileURL: fileURL)
        try store.save(expected)
        try Data("not-json".utf8).write(to: fileURL, options: .atomic)

        let recovered = try XCTUnwrap(store.load())

        XCTAssertEqual(recovered.activeAccountID, account.id)
        XCTAssertEqual(recovered.accounts, [account])
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

    func testUnknownOrExcessiveNotificationPreferencesDecodeAsOff() throws {
        for encoded in [#""unexpected:5""#, #""before:10081""#] {
            let data = try XCTUnwrap(encoded.data(using: .utf8))
            let preference = try JSONDecoder().decode(
                NotificationPreference.self,
                from: data
            )
            XCTAssertEqual(preference, .none)
        }
    }

    func testNotificationPlannerKeepsTheNearestSixtyFourReminders() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 8))
        )
        let todos = try (1...70).map { offset -> TodoEntry in
            let day = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: now))
            let id = try XCTUnwrap(
                UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", offset))
            )
            return TodoEntry(
                id: id,
                title: "Reminder \(offset)",
                description: nil,
                doDate: day,
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
                notificationPreference: .atTime,
                labels: nil,
                timeSessions: nil,
                subtasks: nil,
                assigneeId: nil
            )
        }

        let planned = NotificationSchedulePlanner.plan(
            todos: Array(todos.reversed()),
            categories: [],
            now: now
        )

        XCTAssertEqual(
            planned.count,
            NotificationSchedulePlanner.maximumPendingNotifications
        )
        XCTAssertEqual(planned.first?.title, "Reminder 1")
        XCTAssertEqual(planned.last?.title, "Reminder 64")
    }

    func testNotificationPlannerToleratesDuplicateCategoryIDs() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 8))
        )
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let categoryID = UUID()
        let categories = [
            Category(
                id: categoryID,
                name: "First",
                colorHex: "7C6FF7",
                icon: nil,
                notes: nil,
                notificationPreference: .atTime
            ),
            Category(
                id: categoryID,
                name: "Duplicate",
                colorHex: "60A5FA",
                icon: nil,
                notes: nil,
                notificationPreference: .none
            ),
        ]
        var todo = makeTodo(title: "Inherited reminder", plannedStartTime: "09:00")
        todo.doDate = tomorrow
        todo.categoryId = categoryID

        let planned = NotificationSchedulePlanner.plan(
            todos: [todo],
            categories: categories,
            now: now
        )

        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.title, todo.title)
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

    func testOverdueTaskSplitsBeforeOffTimeThenMovesWholeTaskWhenTooLittleTimeRemains() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 20))
        )
        let later = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 20, minute: 50))
        )
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))

        viewModel.setOffTime(enabled: true, startMinutes: 21 * 60, endMinutes: 7 * 60)
        viewModel.createTodo(
            title: "Hour of work",
            doDate: now,
            plannedStartTime: "19:00",
            plannedDuration: 3_600
        )

        viewModel.pushOverdueTasks(at: now)

        let todayPiece = try XCTUnwrap(viewModel.todos.first { $0.title == "Hour of work" })
        let continuation = try XCTUnwrap(viewModel.todos.first { $0.splitParentID == todayPiece.id })
        XCTAssertEqual(todayPiece.plannedStartTime, "20:05")
        XCTAssertEqual(todayPiece.plannedDuration, 55 * 60)
        XCTAssertTrue(calendar.isDate(continuation.doDate, inSameDayAs: tomorrow))
        XCTAssertEqual(continuation.plannedDuration, 5 * 60)

        viewModel.pushOverdueTasks(at: later)

        let wholeTask = try XCTUnwrap(viewModel.todos.first { $0.title == "Hour of work" })
        XCTAssertTrue(calendar.isDate(wholeTask.doDate, inSameDayAs: tomorrow))
        XCTAssertEqual(wholeTask.plannedStartTime, "07:00")
        XCTAssertEqual(wholeTask.plannedDuration, 60 * 60)
        XCTAssertNil(wholeTask.splitOriginalDuration)
        XCTAssertFalse(viewModel.todos.contains { $0.splitParentID == wholeTask.id })
    }

    func testPushedRecurringTaskKeepsTheNextDaysOccurrence() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 21, minute: 50))
        )
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))

        viewModel.createTodo(
            title: "Work out",
            doDate: now,
            plannedStartTime: "20:00",
            plannedDuration: 1_800,
            recurrenceFrequency: .daily
        )

        viewModel.pushOverdueTasks(at: now)

        let tomorrowWorkouts = viewModel.todos.filter {
            $0.title == "Work out" && calendar.isDate($0.doDate, inSameDayAs: tomorrow)
        }
        XCTAssertEqual(tomorrowWorkouts.count, 2)
        XCTAssertEqual(Set(tomorrowWorkouts.compactMap(\.plannedStartTime)), Set(["07:00", "20:00"]))
    }

    func testUntimedTasksFillGapsWithoutMovingTimedTasks() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 24, hour: 9, minute: 10))
        )

        viewModel.createTodo(
            title: "Appointment",
            doDate: now,
            plannedStartTime: "09:15",
            plannedDuration: 1_800
        )
        viewModel.createTodo(
            title: "Clean room",
            doDate: now,
            plannedStartTime: nil,
            plannedDuration: 900
        )

        viewModel.pushOverdueTasks(at: now)

        let appointment = try XCTUnwrap(viewModel.todos.first { $0.title == "Appointment" })
        let storedFlexibleTask = try XCTUnwrap(viewModel.todos.first { $0.title == "Clean room" })
        let displayedFlexibleTask = try XCTUnwrap(
            viewModel.calendarTodos(on: now, at: now).first { $0.title == "Clean room" }
        )

        XCTAssertEqual(appointment.plannedStartTime, "09:15")
        XCTAssertNil(storedFlexibleTask.plannedStartTime)
        XCTAssertEqual(displayedFlexibleTask.plannedStartTime, "09:45")
    }

    func testCalendarSequentialLayoutStacksTransitiveOverlaps() {
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

        let layout = CalendarSequentialLayout.compute(for: [first, middle, last])

        XCTAssertEqual(layout[first.id], 9 * 60)
        XCTAssertEqual(layout[middle.id], 10 * 60)
        XCTAssertEqual(layout[last.id], 11 * 60)
    }

    func testCalendarSequentialLayoutUsesMinimumDisplayDurationForShortTasks() {
        let first = makeTodo(
            title: "First short task",
            plannedStartTime: "09:00",
            plannedDuration: 5 * 60
        )
        let second = makeTodo(
            title: "Second short task",
            plannedStartTime: "09:10",
            plannedDuration: 5 * 60
        )

        let layout = CalendarSequentialLayout.compute(for: [first, second])

        XCTAssertEqual(layout[first.id], 9 * 60)
        XCTAssertEqual(layout[second.id], 9 * 60 + 15)
    }

    func testReflowRestoresTaskToItsOriginalPlannedTimeAfterEarlierTasksFinish() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let day = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 30, hour: 15))
        )

        for hour in 13...16 {
            viewModel.createTodo(
                title: "Task \(hour)",
                doDate: day,
                plannedStartTime: String(format: "%02d:00", hour),
                plannedDuration: 60 * 60
            )
        }

        viewModel.pushOverdueTasks(at: day)
        XCTAssertEqual(
            viewModel.todos.first { $0.title == "Task 16" }?.plannedStartTime,
            "18:05"
        )

        for index in viewModel.todos.indices where viewModel.todos[index].title != "Task 16" {
            viewModel.todos[index].status = .completed
        }
        viewModel.pushOverdueTasks(at: day)

        XCTAssertEqual(
            viewModel.todos.first { $0.title == "Task 16" }?.plannedStartTime,
            "16:00"
        )
    }

    func testDraggingLaterTaskEarlierShiftsTasksIntoScheduledStartTimes() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let day = Date(timeIntervalSince1970: 1_700_000_000)

        viewModel.createTodo(title: "Morning", doDate: day, plannedStartTime: "10:00", plannedDuration: 7_200)
        viewModel.createTodo(title: "Afternoon", doDate: day, plannedStartTime: "13:00", plannedDuration: 3_600)
        viewModel.createTodo(title: "Evening", doDate: day, plannedStartTime: "17:00", plannedDuration: 3_600)

        var moved = try XCTUnwrap(viewModel.todos.first { $0.title == "Evening" })
        moved.plannedStartTime = "10:00"
        viewModel.updateTodo(moved)

        XCTAssertEqual(viewModel.todos.first { $0.title == "Evening" }?.plannedStartTime, "10:00")
        XCTAssertEqual(viewModel.todos.first { $0.title == "Morning" }?.plannedStartTime, "13:00")
        XCTAssertEqual(viewModel.todos.first { $0.title == "Afternoon" }?.plannedStartTime, "17:00")
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

    func testCustomRecurrenceDoesNotPreGenerateFutureTasks() throws {
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

        XCTAssertEqual(viewModel.todos.count, 1)
    }

    func testMonthlyRecurrenceDoesNotPreGenerateFutureTasks() throws {
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

        XCTAssertEqual(viewModel.todos.count, 1)
    }

    func testLegacyCloudAccountIsExcludedFromLocalOnlyVersionOne() throws {
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

        XCTAssertEqual(viewModel.availableAccounts.map(\.id), [local.id])
        XCTAssertEqual(viewModel.todos.map(\.title), ["Local only"])
    }

    func testDeletingCategoryUnassignsCategoryFromTasksWithoutDeletingTasks() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNotNil(
            viewModel.addCategory(name: "Work", colorHex: "7C6FF7", icon: "💼")
        )
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

    func testTrackedWorkStaysOutOfListAndRequiresFifteenMinutesForCalendar() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let todoID = UUID()
        let todo = TodoEntry(
            id: todoID, title: "Quick task", description: nil,
            doDate: start, dueDate: nil, dueTime: nil, descriptiveDeadline: nil,
            plannedStartTime: "10:00", plannedDuration: 1_800, categoryId: nil,
            status: .completed, priority: nil, location: nil, reminder: nil,
            labels: nil,
            timeSessions: [TimeSession(id: UUID(), todoId: todoID, start: start,
                                       end: start.addingTimeInterval(60), duration: 60)],
            subtasks: nil, assigneeId: nil
        )
        viewModel.todos = [todo]

        XCTAssertTrue(viewModel.todos(on: start).isEmpty)
        XCTAssertFalse(viewModel.hasCalendarWorkRecord(todo))

        let unstarted = TodoEntry(
            id: UUID(), title: "Unstarted task", description: nil,
            doDate: start, dueDate: nil, dueTime: nil, descriptiveDeadline: nil,
            plannedStartTime: "10:00", plannedDuration: 1_800, categoryId: nil,
            status: .completed, priority: nil, location: nil, reminder: nil,
            labels: nil, timeSessions: nil, subtasks: nil, assigneeId: nil
        )
        viewModel.todos.append(unstarted)
        XCTAssertFalse(viewModel.todos(on: start).contains { $0.id == unstarted.id })
    }

    func testCalendarHistoryUsesTimerSessionsWithoutCreatingContinuationTodos() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let todo = makeTodo(title: "Write outline", plannedStartTime: "09:00")
        let session = TimeSession(
            id: UUID(), todoId: todo.id, start: start,
            end: start.addingTimeInterval(15 * 60), duration: 15 * 60
        )
        var trackedTodo = todo
        trackedTodo.timeSessions = [session]
        viewModel.todos = [trackedTodo]

        let calendarTodos = viewModel.calendarTodos(on: start, at: start.addingTimeInterval(15 * 60))
        XCTAssertEqual(viewModel.todos.count, 1)
        XCTAssertEqual(calendarTodos.map(\.title), ["Write outline"])
        XCTAssertEqual(calendarTodos.first?.plannedDuration, 15 * 60)
        XCTAssertEqual(calendarTodos.first?.id, session.id)
    }

    func testCalendarHistoryPreservesAnHourLongRecordedDuration() throws {
        let (viewModel, directory) = makeViewModel()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let todo = makeTodo(title: "Deep work", plannedStartTime: "09:00")
        let session = TimeSession(
            id: UUID(), todoId: todo.id, start: start,
            end: start.addingTimeInterval(60 * 60), duration: 60 * 60
        )
        var trackedTodo = todo
        trackedTodo.timeSessions = [session]
        viewModel.todos = [trackedTodo]

        let calendarTodos = viewModel.calendarTodos(on: start, at: start.addingTimeInterval(60 * 60))

        XCTAssertEqual(calendarTodos.first?.plannedDuration, 60 * 60)
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
