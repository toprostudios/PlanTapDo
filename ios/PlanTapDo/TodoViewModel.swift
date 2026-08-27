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
        didSet { workspaceContentDidChange() }
    }
    @Published var categories: [Category] = [] {
        didSet { workspaceContentDidChange() }
    }
    @Published var locationTravelTimes: [String: Int] = [:] {
        didSet { workspaceContentDidChange() }
    }
    @Published var focusBlocks: [FocusBlock] = [] {
        didSet { persistAppState() }
    }
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    @Published var accountMessage: String? = nil
    @Published var pendingVerificationEmail: String? = nil
    @Published var pendingPasswordResetEmail: String? = nil
    @Published var isMFAEnabled = false
    @Published var mfaSetupSecret: String? = nil
    @Published var mfaRecoveryCodes: [String] = []

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
    /// When enabled, starting another task records the current segment and
    /// continues the unfinished work later in the schedule.
    @Published var automaticallySwitchRunningTask: Bool {
        didSet { UserDefaults.standard.set(automaticallySwitchRunningTask, forKey: "automaticallySwitchRunningTask") }
    }

    // MARK: - Timer State
    @Published var activeTimerTodoId: UUID? = nil
    @Published var timerSecondsElapsed: Int = 0
    @Published private(set) var startUndoTitle: String?
    private var timer: Timer? = nil
    private var activeTimerSessionId: UUID? = nil

    private var localWorkspaces: [UUID: WorkspaceState] = [:]
    private var needsCloudSync = false
    private var deletedTodoIDs = Set<UUID>()
    private var deletedCategoryIDs = Set<UUID>()
    private var deletedSessionIDs = Set<UUID>()
    private var cloudMutationGeneration = 0
    private var cloudSyncWorkItem: DispatchWorkItem?
    private var isCloudSyncInFlight = false

    private struct StartUndoSnapshot {
        let todo: TodoEntry
        let sessionId: UUID
    }

    private var startUndoSnapshot: StartUndoSnapshot?
    private var startUndoTimer: Timer?

    var canUndoLastStart: Bool { startUndoSnapshot != nil }
#if TEAM_VIEW_ENABLED
    // Deactivated legacy Team state. This flag is intentionally undefined in
    // every active build configuration, excluding it from app builds.
    @Published var teamReviewPeople: [UserAccount] = []
    var isProReviewDemo: Bool { userAccount.tier == "Pro Demo" }
#endif

    var timerFormatted: String {
        let mins = timerSecondsElapsed / 60
        let secs = timerSecondsElapsed % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    func startTimer(for todo: TodoEntry) {
        guard let idx = todos.firstIndex(where: { $0.id == todo.id }) else { return }

        let now = Date()
        if activeTimerTodoId != nil {
            guard automaticallySwitchRunningTask else { return }
            handoffRunningTask(at: now)
        }

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
        // A running task is the live schedule. Put its single calendar card at
        // the moment it was started, then move the remaining pending cards out
        // of its way. The timer session remains audit data, not a second block.
        todos[idx].doDate = Calendar.current.startOfDay(for: now)
        todos[idx].plannedStartTime = Self.timeString(from: Self.minutes(from: now))
        var sessions = todos[idx].timeSessions ?? []
        sessions.append(session)
        todos[idx].timeSessions = sessions
        activeTimerTodoId = todo.id
        activeTimerSessionId = session.id

        timerSecondsElapsed = 0
        startTimerTicker()
        pushOverdueTasks(at: now)
    }

    var canStartAnotherTask: Bool {
        activeTimerTodoId == nil || automaticallySwitchRunningTask
    }

    private func handoffRunningTask(at end: Date) {
        guard let activeID = activeTimerTodoId,
              let index = todos.firstIndex(where: { $0.id == activeID }) else {
            clearTimerState()
            return
        }

        let original = todos[index]
        let elapsed: TimeInterval
        if let session = original.timeSessions?.first(where: { $0.id == activeTimerSessionId }) {
            elapsed = max(60, end.timeIntervalSince(session.start))
        } else {
            elapsed = max(60, TimeInterval(timerSecondsElapsed))
        }
        let remaining = max(0, original.plannedDuration - elapsed)

        stopTimer()
        guard let stoppedIndex = todos.firstIndex(where: { $0.id == activeID }) else { return }
        // Preserve the completed recorded segment as this task's one card.
        todos[stoppedIndex].plannedDuration = elapsed

        // The unfinished portion remains a task and enters directly after the
        // newly started task when the live schedule is reflowed.
        guard remaining >= 60 else { return }
        let continuation = TodoEntry(
            id: UUID(),
            title: original.title,
            description: original.description,
            doDate: Calendar.current.startOfDay(for: end),
            dueDate: original.dueDate,
            dueTime: original.dueTime,
            descriptiveDeadline: original.descriptiveDeadline,
            plannedStartTime: Self.timeString(from: Self.minutes(from: end)),
            plannedDuration: remaining,
            categoryId: original.categoryId,
            status: .pending,
            priority: original.priority,
            location: original.location,
            reminder: original.reminder,
            notificationPreference: original.notificationPreference,
            labels: original.labels,
            timeSessions: nil,
            subtasks: original.subtasks,
            assigneeId: original.assigneeId,
            recurrenceFrequency: .none
        )
        todos.append(continuation)
    }

    private func startTimerTicker() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.timerSecondsElapsed += 1
                // Reflow on the five-minute scheduler boundary. The card itself
                // redraws every second from timerSecondsElapsed.
                if self?.timerSecondsElapsed.isMultiple(of: 300) == true {
                    self?.pushOverdueTasks()
                }
            }
        }
    }

    /// The duration used by the calendar's one task card. A running task keeps
    /// its planned size until it runs long, then grows with the stopwatch.
    func calendarDuration(for todo: TodoEntry, at date: Date = Date()) -> TimeInterval {
        let planned = max(60, todo.plannedDuration)
        guard todo.id == activeTimerTodoId,
              let session = todo.timeSessions?.first(where: { $0.id == activeTimerSessionId })
        else { return planned }
        return max(planned, date.timeIntervalSince(session.start))
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
            }
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
        let fallbackAccounts = [personalAccount]
        let persistedState = stateStore.load()
        let storedAccounts = persistedState?.accounts.isEmpty == false
            ? persistedState!.accounts
            : fallbackAccounts
        // Preserve old local Team-demo workspace data, but do not expose its
        // account in the active app.
        // Version 1 is intentionally local-only. Do not restore or activate a
        // legacy cloud account from an earlier development build.
        let restoredAccounts = storedAccounts.filter { !$0.isCloudSynced && $0.tier != "Pro Demo" }
        let activeAccounts = restoredAccounts.isEmpty ? fallbackAccounts : restoredAccounts
        let restoredAccount = activeAccounts.first {
            $0.id == persistedState?.activeAccountID
        } ?? activeAccounts[0]

        self.userAccount = restoredAccount
        self.availableAccounts = activeAccounts
        self.showCompletedTasks = UserDefaults.standard.bool(forKey: "showCompletedTasks")
        self.automaticallySwitchRunningTask = (UserDefaults.standard.object(forKey: "automaticallySwitchRunningTask") as? Bool) ?? true
        let persistedWorkspaces = persistedState?.workspaces ?? [personalAccount.id: .empty]
        self.localWorkspaces = persistedWorkspaces.filter { accountID, _ in
            activeAccounts.contains { $0.id == accountID }
        }

        let workspace = localWorkspaces[restoredAccount.id] ?? .empty
        self.todos = workspace.todos
        self.categories = workspace.categories
        self.locationTravelTimes = workspace.locationTravelTimes
        self.focusBlocks = workspace.focusBlocks
        self.needsCloudSync = workspace.needsCloudSync
        self.deletedTodoIDs = workspace.deletedTodoIDs
        self.deletedCategoryIDs = workspace.deletedCategoryIDs
        self.deletedSessionIDs = workspace.deletedSessionIDs

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

        if restoredAccount.isCloudSynced,
                  let tokens = credentialStore.load(accountID: restoredAccount.id) {
            api.setAuthTokens(tokens, notify: false)
        } else {
            api.clearAuthTokens(notify: false)
        }
        retryPendingLogouts()
        restoreActiveTimerIfNeeded()
        persistAppState()
        synchronizeNotifications()
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
        restoreWorkspace(for: account)
        restoreActiveTimerIfNeeded()
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

    func registerAndSwitchAccount(username: String, email: String, password: String) {
        guard !username.isEmpty && !email.isEmpty && !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        accountMessage = nil

        api.registerAccount(username: username, email: email, password: password)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] response in
                self?.pendingVerificationEmail = email
                self?.accountMessage = response.detail
            }
            .store(in: &cancellables)
    }

    func confirmEmailAndSwitchAccount(email: String, code: String) {
        guard !email.isEmpty, !code.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        accountMessage = nil

        api.confirmEmail(email: email, code: code)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] response in
                guard let self else { return }
                self.pendingVerificationEmail = nil
                self.isMFAEnabled = response.mfaEnabled
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

    func resendEmailVerification(email: String) {
        api.resendEmailVerification(email: email)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] response in
                self?.accountMessage = response.detail
            }
            .store(in: &cancellables)
    }

    func requestPasswordReset(email: String) {
        guard !email.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        accountMessage = nil
        api.requestPasswordReset(email: email)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] response in
                self?.pendingPasswordResetEmail = email
                self?.accountMessage = response.detail
            }
            .store(in: &cancellables)
    }

    func confirmPasswordReset(email: String, code: String, newPassword: String) {
        guard !email.isEmpty, !code.isEmpty, newPassword.count >= 15 else { return }
        isLoading = true
        errorMessage = nil
        accountMessage = nil
        api.confirmPasswordReset(email: email, code: code, newPassword: newPassword)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                switch completion {
                case .finished:
                    self?.pendingPasswordResetEmail = nil
                    self?.accountMessage = "Password updated. Sign in with your new password."
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { _ in }
            .store(in: &cancellables)
    }

    func loginAndSwitchAccount(username: String, password: String, mfaCode: String = "") {
        guard !username.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        api.login(username: username, password: password, mfaCode: mfaCode)
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
                self.isMFAEnabled = profile.mfaEnabled
                self.activateCloudAccount(account, tokens: tokens)
            }
            .store(in: &cancellables)
    }

    func signOutCloudAccount() {
        guard userAccount.isCloudSynced else { return }
        let signedOutID = userAccount.id
        if let tokens = credentialStore.load(accountID: signedOutID) {
            credentialStore.savePendingLogout(tokens, accountID: signedOutID)
        }
        api.logout()
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .finished = completion {
                        self?.credentialStore.deletePendingLogout(accountID: signedOutID)
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        completeLocalSignOut(accountID: signedOutID)
    }

    func revokeAllSessionsAndSignOut() {
        guard userAccount.isCloudSynced else { return }
        let signedOutID = userAccount.id
        isLoading = true
        errorMessage = nil
        api.revokeAllSessions()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                switch completion {
                case .finished:
                    self?.credentialStore.deletePendingLogout(accountID: signedOutID)
                    self?.completeLocalSignOut(accountID: signedOutID)
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { _ in }
            .store(in: &cancellables)
    }

    func deleteCloudAccount(password: String, mfaCode: String = "") {
        guard userAccount.isCloudSynced, !password.isEmpty else { return }
        let deletedAccountID = userAccount.id
        isLoading = true
        errorMessage = nil
        accountMessage = nil

        api.deleteAccount(password: password, mfaCode: mfaCode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] _ in
                guard let self else { return }
                self.completeLocalSignOut(accountID: deletedAccountID)
                self.accountMessage = "Your cloud account and synced data were deleted."
            }
            .store(in: &cancellables)
    }

    func startMFASetup(password: String) {
        guard userAccount.isCloudSynced, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        accountMessage = nil
        api.startMFASetup(password: password)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] response in
                self?.mfaSetupSecret = response.secret
                self?.accountMessage = "Add this key to your authenticator, then enter its code."
            }
            .store(in: &cancellables)
    }

    func confirmMFA(code: String) {
        guard !code.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        api.confirmMFA(code: code)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] response in
                guard let self else { return }
                self.api.setAuthTokens(response.tokens, notify: false)
                self.credentialStore.save(response.tokens, accountID: self.userAccount.id)
                self.isMFAEnabled = true
                self.mfaSetupSecret = nil
                self.mfaRecoveryCodes = response.recoveryCodes
                self.accountMessage = "MFA is enabled. Save every recovery code now."
            }
            .store(in: &cancellables)
    }

    func disableMFA(password: String, code: String) {
        guard !password.isEmpty, !code.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        api.disableMFA(password: password, code: code)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case let .failure(error) = completion {
                    self?.errorMessage = error.localizedDescription
                }
            } receiveValue: { [weak self] response in
                guard let self else { return }
                self.api.setAuthTokens(response.tokens, notify: false)
                self.credentialStore.save(response.tokens, accountID: self.userAccount.id)
                self.isMFAEnabled = false
                self.mfaRecoveryCodes = []
                self.accountMessage = "MFA is disabled."
            }
            .store(in: &cancellables)
    }

    private func completeLocalSignOut(accountID signedOutID: UUID) {
        credentialStore.delete(accountID: signedOutID)
        api.clearAuthTokens(notify: false)
        availableAccounts.removeAll { $0.id == signedOutID }
        isMFAEnabled = false
        mfaSetupSecret = nil
        mfaRecoveryCodes = []
        guard let fallback = availableAccounts.first(where: { !$0.isCloudSynced }) else { return }
        switchAccount(fallback)
        localWorkspaces.removeValue(forKey: signedOutID)
        persistAppState()
    }

    private func retryPendingLogouts() {
        for pending in credentialStore.loadPendingLogouts() {
            api.retryLogout(refreshToken: pending.tokens.refresh)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] completion in
                    if case .finished = completion {
                        self?.credentialStore.deletePendingLogout(
                            accountID: pending.accountID
                        )
                    }
                } receiveValue: { _ in }
                .store(in: &cancellables)
        }
    }

    private func activateCloudAccount(_ account: UserAccount, tokens: APIClient.AuthTokens) {
        saveActiveWorkspace()
        let wasRestoringState = isRestoringState
        isRestoringState = true
        availableAccounts.removeAll { $0.id == account.id }
        availableAccounts.append(account)
        userAccount = account
        restoreWorkspace(for: account)
#if TEAM_VIEW_ENABLED
        teamReviewPeople = []
#endif
        isRestoringState = wasRestoringState
        credentialStore.save(tokens, accountID: account.id)
        api.setAuthTokens(tokens, notify: false)
        if !wasRestoringState {
            persistAppState()
        }
        fetchTodos()
    }

    #if TEAM_VIEW_ENABLED
    // MARK: - Deactivated Local Pro Review Demo
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

    #endif

    private func saveActiveWorkspace() {
        localWorkspaces[userAccount.id] = WorkspaceState(
            todos: todos,
            categories: categories,
            locationTravelTimes: locationTravelTimes,
            focusBlocks: focusBlocks,
            needsCloudSync: needsCloudSync,
            deletedTodoIDs: deletedTodoIDs,
            deletedCategoryIDs: deletedCategoryIDs,
            deletedSessionIDs: deletedSessionIDs
        )
    }

    private func restoreWorkspace(for account: UserAccount) {
        let workspace = localWorkspaces[account.id] ?? .empty
        todos = workspace.todos
        categories = workspace.categories
        locationTravelTimes = workspace.locationTravelTimes
        focusBlocks = workspace.focusBlocks
        needsCloudSync = workspace.needsCloudSync
        deletedTodoIDs = workspace.deletedTodoIDs
        deletedCategoryIDs = workspace.deletedCategoryIDs
        deletedSessionIDs = workspace.deletedSessionIDs
#if TEAM_VIEW_ENABLED
        teamReviewPeople = []
#endif
        errorMessage = nil
    }

    private func persistAppState() {
        guard !isRestoringState else { return }
        localWorkspaces[userAccount.id] = WorkspaceState(
            todos: todos,
            categories: categories,
            locationTravelTimes: locationTravelTimes,
            focusBlocks: focusBlocks,
            needsCloudSync: needsCloudSync,
            deletedTodoIDs: deletedTodoIDs,
            deletedCategoryIDs: deletedCategoryIDs,
            deletedSessionIDs: deletedSessionIDs
        )
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

    private func workspaceContentDidChange() {
        guard !isRestoringState else { return }
        if userAccount.isCloudSynced {
            needsCloudSync = true
            cloudMutationGeneration += 1
            scheduleCloudSync()
        }
        persistAppState()
        synchronizeNotifications()
    }

    private func synchronizeNotifications() {
        LocalNotificationManager.shared.synchronize(todos: todos, categories: categories)
    }

    private func scheduleCloudSync() {
        guard userAccount.isCloudSynced, api.isAuthenticated else { return }
        cloudSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.synchronizeWorkspaceWithCloud()
        }
        cloudSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: workItem)
    }

    private func allTimeSessions() -> [TimeSession] {
        todos
            .flatMap { $0.timeSessions ?? [] }
            .filter { $0.todoId != nil }
            .sorted { $0.start < $1.start }
    }

    private func synchronizeWorkspaceWithCloud() {
        guard userAccount.isCloudSynced,
              api.isAuthenticated,
              !isCloudSyncInFlight else { return }

        isCloudSyncInFlight = true
        isLoading = true
        errorMessage = nil
        let accountID = userAccount.id
        let generation = cloudMutationGeneration
        let publisher: AnyPublisher<APIClient.SyncStateResponse, Error>
        if needsCloudSync {
            publisher = api.syncWorkspace(
                categories: categories,
                todos: todos,
                sessions: allTimeSessions(),
                travelTimes: locationTravelTimes,
                deletedTodoIDs: deletedTodoIDs,
                deletedCategoryIDs: deletedCategoryIDs,
                deletedSessionIDs: deletedSessionIDs
            )
        } else {
            publisher = api.fetchSyncState()
        }

        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self else { return }
                self.isCloudSyncInFlight = false
                self.isLoading = false
                guard self.userAccount.id == accountID else {
                    self.fetchTodos()
                    return
                }
                if case let .failure(error) = completion {
                    self.errorMessage = error.localizedDescription
                } else if self.needsCloudSync && self.api.isAuthenticated {
                    self.scheduleCloudSync()
                }
            } receiveValue: { [weak self] state in
                guard let self else { return }
                guard self.userAccount.id == accountID else { return }
                guard self.cloudMutationGeneration == generation else {
                    self.scheduleCloudSync()
                    return
                }
                self.applyCloudState(state)
                self.needsCloudSync = false
                self.deletedTodoIDs.removeAll()
                self.deletedCategoryIDs.removeAll()
                self.deletedSessionIDs.removeAll()
                self.persistAppState()
                self.restoreActiveTimerIfNeeded()
                self.pushOverdueTasks()
            }
            .store(in: &cancellables)
    }

    private func applyCloudState(_ state: APIClient.SyncStateResponse) {
        let wasRestoringState = isRestoringState
        isRestoringState = true
        var syncedTodos = state.todos
        for session in state.sessions {
            guard let todoId = session.todoId,
                  let index = syncedTodos.firstIndex(where: { $0.id == todoId }) else { continue }
            var normalizedSession = session
            if let duration = normalizedSession.duration {
                normalizedSession.duration = duration * 60
            }
            var sessions = syncedTodos[index].timeSessions ?? []
            if let existingIndex = sessions.firstIndex(where: { $0.id == normalizedSession.id }) {
                sessions[existingIndex] = normalizedSession
            } else {
                sessions.append(normalizedSession)
            }
            syncedTodos[index].timeSessions = sessions.sorted { $0.start < $1.start }
        }
        todos = syncedTodos
        categories = state.categories
        applyTravelTimes(state.travelTimes)
        isRestoringState = wasRestoringState
    }

    private func restoreActiveTimerIfNeeded() {
        guard activeTimerTodoId == nil else { return }
        let openSessions = todos.flatMap { todo in
            (todo.timeSessions ?? [])
                .filter { $0.end == nil }
                .map { (todo.id, $0) }
        }
        guard let latest = openSessions.max(by: { $0.1.start < $1.1.start }) else { return }
        activeTimerTodoId = latest.0
        activeTimerSessionId = latest.1.id
        timerSecondsElapsed = max(0, Int(Date().timeIntervalSince(latest.1.start)))
        startTimerTicker()
    }

    // MARK: - Fetch
    func fetchTodos() {
        guard userAccount.isCloudSynced, api.isAuthenticated else {
            pushOverdueTasks()
            return
        }
        synchronizeWorkspaceWithCloud()
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
        notificationPreference: NotificationPreference? = nil,
        labels: [String]? = nil,
        recurrenceFrequency: RecurrenceFrequency = .none,
        recurrenceWeekdays: [Int]? = nil
    ) {
        let recurrenceSeriesId = recurrenceFrequency == .none ? nil : UUID()
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
            notificationPreference: notificationPreference,
            labels: labels,
            timeSessions: nil,
            subtasks: [],
            assigneeId: nil,
            recurrenceFrequency: recurrenceFrequency,
            recurrenceWeekdays: recurrenceWeekdays,
            recurrenceSeriesId: recurrenceSeriesId
        )
        todos.append(newTodo)
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
        deletedTodoIDs.insert(id)
        for session in removedTodo?.timeSessions ?? [] {
            deletedSessionIDs.insert(session.id)
        }
        todos.removeAll { $0.id == id }
        LocalNotificationManager.shared.removeNotifications(for: id)
    }

    func finishTodo(id todoId: UUID) {
        if let idx = todos.firstIndex(where: { $0.id == todoId }) {
            if activeTimerTodoId == todoId {
                stopTimer()
            }
            todos[idx].status = .completed
            todos[idx].completedAt = Date()
            ensureFutureOccurrence(after: todos[idx])
        }
    }

    func updateTodo(_ todo: TodoEntry) {
        var updatedTodo = todo
        if updatedTodo.recurrenceFrequency != .none && updatedTodo.recurrenceSeriesId == nil {
            updatedTodo.recurrenceSeriesId = UUID()
        }
        applyFocusRule(to: &updatedTodo)
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index] = updatedTodo
        }
    }

    /// v1 has one global off-time window. Per-profile and per-category
    /// schedules are intentionally deferred until a later release.
    func setOffTime(enabled: Bool, startMinutes: Int, endMinutes: Int) {
        guard enabled, endMinutes != startMinutes else {
            focusBlocks = []
            saveActiveWorkspace()
            return
        }
        let everyDay = Set(1...7)
        if endMinutes > startMinutes {
            focusBlocks = [FocusBlock(
                name: "Off time", weekdays: everyDay, startMinutes: startMinutes,
                endMinutes: endMinutes, allowedCategoryIds: []
            )]
        } else {
            // The storage model has same-day intervals, so one overnight
            // account-wide window is represented by its two daily segments.
            focusBlocks = [
                FocusBlock(name: "Off time", weekdays: everyDay, startMinutes: startMinutes, endMinutes: 24 * 60, allowedCategoryIds: []),
                FocusBlock(name: "Off time", weekdays: everyDay, startMinutes: 0, endMinutes: endMinutes, allowedCategoryIds: [])
            ]
        }
        applyFocusRulesToScheduledTasks()
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
    }

    // MARK: - Subtask Actions
    func addSubtask(to todoId: UUID, title: String) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let idx = todos.firstIndex(where: { $0.id == todoId }) {
            var subtasks = todos[idx].subtasks ?? []
            subtasks.append(Subtask(id: UUID().uuidString, title: title.trimmingCharacters(in: .whitespaces), isCompleted: false))
            todos[idx].subtasks = subtasks
        }
    }

    func toggleSubtask(todoId: UUID, subtaskId: String) {
        if let todoIdx = todos.firstIndex(where: { $0.id == todoId }),
           var subtasks = todos[todoIdx].subtasks,
           let subIdx = subtasks.firstIndex(where: { $0.id == subtaskId }) {
            subtasks[subIdx].isCompleted.toggle()
            todos[todoIdx].subtasks = subtasks
        }
    }

    func deleteSubtask(todoId: UUID, subtaskId: String) {
        if let todoIdx = todos.firstIndex(where: { $0.id == todoId }),
           var subtasks = todos[todoIdx].subtasks {
            subtasks.removeAll { $0.id == subtaskId }
            todos[todoIdx].subtasks = subtasks
        }
    }

    // MARK: - Recurrence & Live Schedule

    func pushOverdueTasks(at currentDate: Date = Date()) {
        guard !isCloudSyncInFlight else { return }
        materializeDueRecurringOccurrences(at: currentDate)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: currentDate)
        let currentMinutes = calendar.component(.hour, from: currentDate) * 60
            + calendar.component(.minute, from: currentDate)
        // Pending tasks stay just ahead of the time bar when they are not
        // started. At an exact five-minute boundary, use the following slot so
        // the card is visibly pushed rather than remaining under the bar.
        let roundedCurrentMinutes = max(7 * 60, (currentMinutes / 5 + 1) * 5)

        // An unfinished scheduled task simply moves forward. Only timer sessions
        // are historical calendar records; an abandoned plan never leaves a ghost.
        for index in todos.indices where todos[index].status == .pending && todos[index].plannedStartTime != nil {
            let scheduledDay = calendar.startOfDay(for: todos[index].doDate)
            guard scheduledDay < today else { continue }
            todos[index].doDate = today
        }

        let scheduledIndices = todos.indices
            .filter { index in
                let todo = todos[index]
                return calendar.isDate(todo.doDate, inSameDayAs: today)
                    && (todo.status == .pending || todo.id == activeTimerTodoId)
                    && todo.plannedStartTime != nil
            }
            .sorted { lhs, rhs in
                if todos[lhs].id == activeTimerTodoId { return true }
                if todos[rhs].id == activeTimerTodoId { return false }
                return (todos[lhs].plannedStartTime ?? "23:59") < (todos[rhs].plannedStartTime ?? "23:59")
            }

        let movableIDs = Set(scheduledIndices.map { todos[$0].id })
        var cursorDate = today
        var cursorMinute = roundedCurrentMinutes

        for index in scheduledIndices {
            guard let time = todos[index].plannedStartTime else { continue }
            let durationMinutes = min(
                15 * 60,
                max(5, Int(ceil(calendarDuration(for: todos[index], at: currentDate) / 60)))
            )
            let earliestMinute = calendar.isDate(cursorDate, inSameDayAs: today)
                ? max(Self.minutes(from: time), cursorMinute)
                : cursorMinute
            let slot = nextOpenSlot(
                for: todos[index],
                onOrAfter: cursorDate,
                from: earliestMinute,
                ignoring: movableIDs
            )
            let newTime = Self.timeString(from: slot.minute)
            if !calendar.isDate(todos[index].doDate, inSameDayAs: slot.date)
                || todos[index].plannedStartTime != newTime {
                todos[index].doDate = slot.date
                todos[index].plannedStartTime = newTime
            }
            cursorDate = slot.date
            cursorMinute = slot.minute + durationMinutes
            if cursorMinute >= 22 * 60 {
                cursorDate = calendar.date(byAdding: .day, value: 1, to: cursorDate) ?? cursorDate
                cursorMinute = 7 * 60
            }
        }
    }

    private func nextOpenSlot(
        for todo: TodoEntry,
        onOrAfter startDate: Date,
        from startMinute: Int,
        ignoring movableIDs: Set<UUID>
    ) -> (date: Date, minute: Int) {
        let calendar = Calendar.current
        let durationMinutes = min(15 * 60, max(5, Int(todo.plannedDuration / 60)))
        var candidateDate = calendar.startOfDay(for: startDate)
        var candidateMinute = max(7 * 60, startMinute)

        for _ in 0..<366 {
            let allowed = todo.recurrenceFrequency == .none
                ? nextAllowedSlot(for: todo, on: candidateDate, from: candidateMinute)
                : (date: candidateDate, minute: candidateMinute)
            if !calendar.isDate(allowed.date, inSameDayAs: candidateDate) {
                candidateDate = allowed.date
                candidateMinute = allowed.minute
                continue
            }
            candidateMinute = allowed.minute

            let occupied = todos.compactMap { other -> (start: Int, end: Int)? in
                guard other.id != todo.id,
                      !movableIDs.contains(other.id),
                      calendar.isDate(other.doDate, inSameDayAs: candidateDate),
                      other.status != .completed,
                      other.status != .archived,
                      other.status != .skipped,
                      let time = other.plannedStartTime else { return nil }
                let start = Self.minutes(from: time)
                return (start, start + min(15 * 60, max(5, Int(other.plannedDuration / 60))))
            }
            .sorted { $0.start < $1.start }

            var movedPastConflict = false
            for interval in occupied where candidateMinute < interval.end {
                if candidateMinute + durationMinutes <= interval.start {
                    return (candidateDate, candidateMinute)
                }
                candidateMinute = interval.end
                movedPastConflict = true
            }
            if movedPastConflict, todo.recurrenceFrequency == .none {
                let focusAdjusted = nextAllowedSlot(
                    for: todo,
                    on: candidateDate,
                    from: candidateMinute
                )
                if !calendar.isDate(focusAdjusted.date, inSameDayAs: candidateDate) {
                    candidateDate = focusAdjusted.date
                    candidateMinute = focusAdjusted.minute
                    continue
                }
                candidateMinute = focusAdjusted.minute
            }
            if candidateMinute + durationMinutes <= 22 * 60 {
                return (candidateDate, candidateMinute)
            }
            candidateDate = calendar.date(byAdding: .day, value: 1, to: candidateDate) ?? candidateDate
            candidateMinute = 7 * 60
        }
        return (candidateDate, candidateMinute)
    }

    private func applyFocusRulesToScheduledTasks() {
        for index in todos.indices {
            var todo = todos[index]
            guard applyFocusRule(to: &todo) else { continue }
            todos[index] = todo
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
            // Off time is global in v1: no category can be scheduled inside it.
            let applicable = focusBlocks.filter { $0.weekdays.contains(weekday) }

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

    /// Recurrences are created only when their calendar day arrives. This keeps
    /// Upcoming and Tasks from being filled with pre-generated daily copies.
    private func materializeDueRecurringOccurrences(at currentDate: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: currentDate)
        let templates = todos.filter { $0.recurrenceFrequency != .none && $0.doDate < today }
        for template in templates {
            guard let seriesID = template.recurrenceSeriesId,
                  recurrenceApplies(template, on: today),
                  !todos.contains(where: {
                      $0.recurrenceSeriesId == seriesID && calendar.isDate($0.doDate, inSameDayAs: today)
                  }) else { continue }
            todos.append(recurringOccurrence(from: template, on: today))
        }
    }

    private func recurringOccurrence(from template: TodoEntry, on occurrenceDate: Date) -> TodoEntry {
        let calendar = Calendar.current
        let dueDateOffset = template.dueDate.map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: template.doDate), to: calendar.startOfDay(for: $0)).day ?? 0
        }
        let occurrenceDueDate = dueDateOffset.flatMap { calendar.date(byAdding: .day, value: $0, to: occurrenceDate) }
        return TodoEntry(
            id: UUID(), title: template.title, description: template.description,
            doDate: occurrenceDate, dueDate: occurrenceDueDate, dueTime: template.dueTime,
            descriptiveDeadline: template.descriptiveDeadline, plannedStartTime: template.plannedStartTime,
            plannedDuration: template.plannedDuration, categoryId: template.categoryId, status: .pending,
            priority: template.priority, location: template.location, reminder: template.reminder,
            notificationPreference: template.notificationPreference, labels: template.labels, timeSessions: nil,
            subtasks: (template.subtasks ?? []).map { Subtask(id: UUID().uuidString, title: $0.title, isCompleted: false) },
            assigneeId: template.assigneeId, recurrenceFrequency: template.recurrenceFrequency,
            recurrenceWeekdays: template.recurrenceWeekdays, recurrenceSeriesId: template.recurrenceSeriesId
        )
    }

    private func recurrenceApplies(_ template: TodoEntry, on date: Date) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: template.doDate)
        guard date > start else { return false }
        switch template.recurrenceFrequency {
        case .none: return false
        case .daily: return true
        case .weekly:
            return calendar.dateComponents([.day], from: start, to: date).day.map { $0 % 7 == 0 } ?? false
        case .monthly:
            return calendar.component(.day, from: start) == calendar.component(.day, from: date)
        case .custom:
            let weekdays = Set(template.recurrenceWeekdays ?? [calendar.component(.weekday, from: start)])
            return weekdays.contains(calendar.component(.weekday, from: date))
        }
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
        }
    }

    private func ensureFutureOccurrence(after todo: TodoEntry) {
        // Recurring tasks are deliberately created at midnight, not when the
        // previous task is completed.
        materializeDueRecurringOccurrences(at: Date())
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

    private static func minutes(from date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private func cancelSession(id localId: UUID) {
        deletedSessionIDs.insert(localId)
        needsCloudSync = userAccount.isCloudSynced
        persistAppState()
    }

    static let freeCategoryLimit = 2

    func canAddCategory(isPremium: Bool) -> Bool {
        isPremium || categories.count < Self.freeCategoryLimit
    }

    func addCategory(name: String, colorHex: String, icon: String, isPremium: Bool) -> Category? {
        guard canAddCategory(isPremium: isPremium) else { return nil }
        let cat = Category(id: UUID(), name: name, colorHex: colorHex, icon: icon, notes: "# \(icon) \(name) Document\n\nType notes...")
        categories.append(cat)
        return cat
    }

    func updateCategory(_ category: Category) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index] = category
    }

    func deleteCategory(id: UUID) {
        guard categories.contains(where: { $0.id == id }) else { return }
        deletedCategoryIDs.insert(id)
        categories.removeAll { $0.id == id }
        for index in todos.indices where todos[index].categoryId == id {
            todos[index].categoryId = nil
        }
    }
}
