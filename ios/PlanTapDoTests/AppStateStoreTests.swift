import XCTest
@testable import PlanTapDo

final class AppStateStoreTests: XCTestCase {
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
}
