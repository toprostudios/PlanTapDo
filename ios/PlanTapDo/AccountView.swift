// AccountView.swift
import SwiftUI

private enum CloudAuthMode: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case create = "Create Account"
    case reset = "Reset Password"

    var id: String { rawValue }
}

struct AccountView: View {
    @ObservedObject var viewModel: TodoViewModel
    @EnvironmentObject private var subscriptionManager: SubscriptionManager

    @State private var newUsername = ""
    @State private var newEmail = ""
    @State private var newPassword = ""
    @State private var showingAddForm = false
    @State private var authMode: CloudAuthMode = .signIn
    @State private var emailCode = ""
    @State private var mfaCode = ""
    @State private var mfaPassword = ""
    @State private var mfaEnrollmentCode = ""
    @State private var showingRevokeAllConfirmation = false
    @State private var showingDeleteAccount = false
    @State private var deletionPassword = ""
    @State private var deletionMFACode = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                    // Active Account Profile Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(Color.indigo)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Text(viewModel.userAccount.name.prefix(1).uppercased())
                                        .font(.title2.weight(.bold))
                                        .foregroundStyle(.white)
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(viewModel.userAccount.name)
                                        .font(.headline.weight(.bold))
                                    Text("👑 \(subscriptionManager.hasPremium ? "Premium" : viewModel.userAccount.tier)")
                                        .font(.caption2.weight(.heavy))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.indigo.opacity(0.2)))
                                        .foregroundStyle(.indigo)
                                }

                                Text("✉️ \(viewModel.userAccount.email)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Text(accountStatusLabel)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(accountStatusColor.opacity(0.15)))
                                .foregroundStyle(accountStatusColor)

                            if viewModel.userAccount.isCloudSynced {
                                Spacer()
                                Button("Sign Out", role: .destructive) {
                                    viewModel.signOutCloudAccount()
                                }
                                .font(.caption.weight(.semibold))
                                Button("Everywhere", role: .destructive) {
                                    showingRevokeAllConfirmation = true
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
                    .padding(.horizontal)

                    if viewModel.userAccount.isCloudSynced {
                        mfaSecurityCard
                            .padding(.horizontal)

                        accountDeletionCard
                            .padding(.horizontal)
                    }

                    // Switch Accounts List Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("🔄 SWITCH ACCOUNTS")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                showingAddForm.toggle()
                            } label: {
                                Label(showingAddForm ? "Cancel" : "Cloud Account", systemImage: "person.crop.circle.badge.plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.indigo)
                            }
                        }

                        if showingAddForm {
                            VStack(spacing: 10) {
                                if let email = viewModel.pendingVerificationEmail {
                                    verificationForm(email: email)
                                } else if let email = viewModel.pendingPasswordResetEmail {
                                    passwordResetConfirmationForm(email: email)
                                } else {
                                    Picker("Cloud account action", selection: $authMode) {
                                        ForEach(CloudAuthMode.allCases) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    if authMode != .reset {
                                        TextField("Username", text: $newUsername)
                                            .modernTextInput()
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                    }

                                    if authMode != .signIn {
                                        TextField("Email Address", text: $newEmail)
                                            .modernTextInput()
                                            .textInputAutocapitalization(.never)
                                            .keyboardType(.emailAddress)
                                    }

                                    if authMode != .reset {
                                        SecureField("Password", text: $newPassword)
                                            .modernTextInput()
                                    }

                                    if authMode == .signIn {
                                        TextField("MFA or Recovery Code (if enabled)", text: $mfaCode)
                                            .modernTextInput()
                                            .textInputAutocapitalization(.characters)
                                            .autocorrectionDisabled()
                                    }

                                    if authMode == .create,
                                       !newPassword.isEmpty,
                                       newPassword.count < 15 {
                                        Text("Use at least 15 characters.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    Button(authMode.rawValue) {
                                        performAuthAction()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.indigo)
                                    .disabled(authActionDisabled)
                                }

                                accountFeedback
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
                        }

                        ForEach(viewModel.availableAccounts) { acc in
                            let isActive = (acc.id == viewModel.userAccount.id)

                            HStack {
                                Circle()
                                    .fill(isActive ? Color.indigo : Color.secondary.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(acc.name.prefix(1).uppercased())
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(acc.name)
                                        .font(.subheadline.weight(.bold))
                                    Text(acc.email)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if isActive {
                                    Text("Active")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.indigo)
                                } else {
                                    Button("Switch") {
                                        viewModel.switchAccount(acc)
                                    }
                                    .font(.caption.weight(.bold))
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isActive ? Color.indigo.opacity(0.1) : Color.primary.opacity(0.04))
                            )
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.userAccount.id) { _ in
            if !viewModel.userAccount.isCloudSynced {
                showingDeleteAccount = false
                deletionPassword = ""
                deletionMFACode = ""
                return
            }
            newUsername = ""
            newEmail = ""
            newPassword = ""
            showingAddForm = false
        }
        .confirmationDialog(
            "Sign out on every device?",
            isPresented: $showingRevokeAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Revoke Every Session", role: .destructive) {
                viewModel.revokeAllSessionsAndSignOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every phone, tablet, and copied token will need to sign in again.")
        }
        .sheet(isPresented: $showingDeleteAccount) {
            accountDeletionSheet
        }
    }

    private var accountDeletionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DELETE CLOUD ACCOUNT")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.secondary)
            Text("Permanently remove this account")
                .font(.subheadline.weight(.semibold))
            Text("This deletes the cloud account and all synced tasks, categories, and recorded work. This cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Delete Cloud Account", role: .destructive) {
                showingDeleteAccount = true
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.red.opacity(0.06)))
    }

    private var accountDeletionSheet: some View {
        NavigationStack {
            Form {
                Section("Permanent deletion") {
                    Text("All synced tasks, categories, timer history, sessions, and account credentials will be permanently deleted.")
                        .font(.callout)
                    SecureField("Current password", text: $deletionPassword)
                        .textContentType(.password)
                    TextField("MFA or recovery code (if enabled)", text: $deletionMFACode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section {
                    Button(role: .destructive) {
                        viewModel.deleteCloudAccount(
                            password: deletionPassword,
                            mfaCode: deletionMFACode
                        )
                    } label: {
                        HStack {
                            if viewModel.isLoading { ProgressView() }
                            Text("Delete Account Permanently")
                        }
                    }
                    .disabled(deletionPassword.isEmpty || viewModel.isLoading)
                } footer: {
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        deletionPassword = ""
                        deletionMFACode = ""
                        showingDeleteAccount = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func verificationForm(email: String) -> some View {
        Text("Enter the 8-digit code sent to \(email).")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        TextField("Verification Code", text: $emailCode)
            .modernTextInput()
            .keyboardType(.numberPad)
        Button("Verify Email") {
            viewModel.confirmEmailAndSwitchAccount(email: email, code: emailCode)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isLoading || emailCode.count != 8)
        Button("Resend Code") {
            viewModel.resendEmailVerification(email: email)
        }
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private func passwordResetConfirmationForm(email: String) -> some View {
        Text("Enter the code sent to \(email), then choose a new password.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        TextField("Reset Code", text: $emailCode)
            .modernTextInput()
            .keyboardType(.numberPad)
        SecureField("New Password", text: $newPassword)
            .modernTextInput()
        Button("Update Password") {
            viewModel.confirmPasswordReset(
                email: email,
                code: emailCode,
                newPassword: newPassword
            )
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            viewModel.isLoading || emailCode.count != 8 || newPassword.count < 15
        )
    }

    @ViewBuilder
    private var accountFeedback: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if let accountMessage = viewModel.accountMessage {
            Text(accountMessage)
                .font(.caption)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mfaSecurityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACCOUNT SECURITY")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.secondary)
            Text(viewModel.isMFAEnabled ? "MFA is enabled" : "Authenticator MFA")
                .font(.subheadline.weight(.semibold))

            if let secret = viewModel.mfaSetupSecret {
                Text("Authenticator setup key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(secret)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                TextField("6-digit authenticator code", text: $mfaEnrollmentCode)
                    .modernTextInput()
                    .keyboardType(.numberPad)
                Button("Enable MFA") {
                    viewModel.confirmMFA(code: mfaEnrollmentCode)
                }
                .buttonStyle(.borderedProminent)
                .disabled(mfaEnrollmentCode.count != 6 || viewModel.isLoading)
            } else {
                SecureField("Current Password", text: $mfaPassword)
                    .modernTextInput()
                if viewModel.isMFAEnabled {
                    TextField("MFA or Recovery Code", text: $mfaEnrollmentCode)
                        .modernTextInput()
                        .textInputAutocapitalization(.characters)
                    Button("Disable MFA", role: .destructive) {
                        viewModel.disableMFA(
                            password: mfaPassword,
                            code: mfaEnrollmentCode
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        mfaPassword.isEmpty || mfaEnrollmentCode.isEmpty || viewModel.isLoading
                    )
                } else {
                    Button("Start MFA Setup") {
                        viewModel.startMFASetup(password: mfaPassword)
                    }
                    .buttonStyle(.bordered)
                    .disabled(mfaPassword.isEmpty || viewModel.isLoading)
                }
            }

            if !viewModel.mfaRecoveryCodes.isEmpty {
                Text("Recovery codes — save these once")
                    .font(.caption.weight(.semibold))
                Text(viewModel.mfaRecoveryCodes.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            accountFeedback
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
    }

    private var authActionDisabled: Bool {
        viewModel.isLoading
            || (authMode != .reset && newUsername.isEmpty)
            || (authMode == .create && newPassword.count < 15)
            || (authMode == .signIn && newPassword.isEmpty)
            || (authMode != .signIn && newEmail.isEmpty)
    }

    private func performAuthAction() {
        switch authMode {
        case .create:
            viewModel.registerAndSwitchAccount(
                username: newUsername,
                email: newEmail,
                password: newPassword
            )
        case .signIn:
            viewModel.loginAndSwitchAccount(
                username: newUsername,
                password: newPassword,
                mfaCode: mfaCode
            )
        case .reset:
            viewModel.requestPasswordReset(email: newEmail)
        }
    }

    private var accountStatusLabel: String {
        if viewModel.userAccount.isCloudSynced { return "☁️ Cloud Synced" }
        return "📱 Personal Workspace"
    }

    private var accountStatusColor: Color {
        if viewModel.userAccount.isCloudSynced { return .green }
        return .secondary
    }
}

#if TEAM_VIEW_ENABLED
// Deactivated: preserved for a future team-feature rollout. TEAM_VIEW_ENABLED
// is intentionally not defined in any build configuration.
struct ProTeamReviewView: View {
    @ObservedObject var viewModel: TodoViewModel
    @State private var selectedPersonID: UUID?
    @State private var managerView = true

    private var selectedPerson: UserAccount? {
        viewModel.teamReviewPeople.first { $0.id == selectedPersonID }
            ?? viewModel.teamReviewPeople.first
    }

    private var tasks: [TodoEntry] {
        guard let selectedPerson else { return [] }
        return viewModel.todos
            .filter {
                $0.assigneeId == selectedPerson.id.uuidString
                    && Calendar.current.isDateInToday($0.doDate)
            }
            .sorted { ($0.plannedStartTime ?? "23:59") < ($1.plannedStartTime ?? "23:59") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Planned vs actual")
                    .font(.title3.weight(.bold))

                Picker("View", selection: $managerView) {
                    Text("Manager").tag(true)
                    Text("Team").tag(false)
                }
                .pickerStyle(.segmented)

                if managerView {
                    managerCalendar
                } else {
                    teamOverview
                }

                if !managerView { Picker("Person", selection: $selectedPersonID) {
                    ForEach(viewModel.teamReviewPeople) { person in
                        Text(person.name).tag(Optional(person.id))
                    }
                }
                .pickerStyle(.menu) }

                if !managerView && tasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("No tasks for today")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                } else if !managerView {
                    ForEach(tasks) { task in
                        TeamTaskReviewRow(task: task)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(selectedPerson?.name ?? "Team day")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedPersonID = selectedPersonID ?? viewModel.teamReviewPeople.first?.id
        }
    }

    private var teamOverview: some View {
        HStack(spacing: 10) {
            ForEach(viewModel.teamReviewPeople) { person in
                let count = viewModel.todos.filter { $0.assigneeId == person.id.uuidString && Calendar.current.isDateInToday($0.doDate) }.count
                VStack(alignment: .leading, spacing: 4) { Text(person.name).font(.subheadline.weight(.bold)); Text("\(count) tasks today").font(.caption).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.indigo.opacity(0.08)))
            }
        }
    }

    private var managerCalendar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(viewModel.teamReviewPeople) { person in
                    TeamMemberScheduleView(
                        person: person,
                        tasks: viewModel.todos.filter {
                            $0.assigneeId == person.id.uuidString && Calendar.current.isDateInToday($0.doDate)
                        }
                    )
                }
            }
        }
    }
}

/// An at-a-glance, time-positioned schedule for each person rather than a
/// "next task" placeholder. The same task data remains available in Team mode.
private struct TeamMemberScheduleView: View {
    let person: UserAccount
    let tasks: [TodoEntry]
    private let startHour = 7
    private let endHour = 20
    private let hourHeight: CGFloat = 42

    private var scheduleHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(person.name).font(.subheadline.weight(.bold))
                Spacer()
                Text("Today").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(startHour..<endHour, id: \.self) { hour in
                            HStack(alignment: .top) {
                                Text(hourLabel(hour))
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, alignment: .leading)
                                Rectangle().fill(Color.secondary.opacity(0.16)).frame(height: 1)
                            }
                            .frame(height: hourHeight, alignment: .top)
                        }
                    }

                    ForEach(tasks.filter { $0.plannedStartTime != nil }) { task in
                        let minutes = minutes(from: task.plannedStartTime ?? "07:00")
                        let top = CGFloat(minutes - startHour * 60) / 60 * hourHeight
                        let height = max(28, CGFloat(task.plannedDuration / 60) / 60 * hourHeight)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.plannedStartTime ?? "")
                                .font(.system(size: 8, weight: .black))
                            Text(task.title)
                                .font(.system(size: 9, weight: .bold))
                                .lineLimit(2)
                        }
                        .foregroundStyle(.white)
                        .padding(5)
                        .frame(width: max(70, geo.size.width - 40), height: height, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 7).fill(task.status == .completed ? Color.green : Color.indigo))
                        .offset(x: 38, y: max(0, top))
                    }
                }
            }
            .frame(height: scheduleHeight)

            if tasks.isEmpty {
                Text("No work scheduled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 205, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }

    private func minutes(from time: String) -> Int {
        let values = time.split(separator: ":").compactMap { Int($0) }
        guard values.count == 2 else { return startHour * 60 }
        return values[0] * 60 + values[1]
    }

    private func hourLabel(_ hour: Int) -> String {
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display) \(hour >= 12 ? "PM" : "AM")"
    }
}

private struct TeamTaskReviewRow: View {
    let task: TodoEntry

    private var planned: String {
        guard let start = task.plannedStartTime else { return "Unscheduled" }
        let duration = max(1, task.plannedDuration / 60)
        return "Planned: \(start) · \(duration)m"
    }

    private var actual: String {
        guard let session = task.timeSessions?.first else { return "Actual: no activity recorded" }
        let start = session.start.formatted(date: .omitted, time: .shortened)
        let minutes = Int((session.duration ?? session.end?.timeIntervalSince(session.start) ?? 0) / 60)
        return "Actual: \(start) · \(minutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Image(systemName: task.timeSessions?.isEmpty == false ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.timeSessions?.isEmpty == false ? .green : .secondary)
            }
            Text(planned)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(actual)
                .font(.caption.weight(.medium))
                .foregroundStyle(task.timeSessions?.isEmpty == false ? .green : .secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
    }
}
#endif

struct AccountView_Previews: PreviewProvider {
    static var previews: some View { AccountView(viewModel: TodoViewModel()) }
}
