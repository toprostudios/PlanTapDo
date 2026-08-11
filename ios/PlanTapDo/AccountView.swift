// AccountView.swift
import SwiftUI

private enum CloudAuthMode: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case create = "Create Account"

    var id: String { rawValue }
}

struct AccountView: View {
    @ObservedObject var viewModel: TodoViewModel

    @State private var newUsername = ""
    @State private var newEmail = ""
    @State private var newPassword = ""
    @State private var showingAddForm = false
    @State private var authMode: CloudAuthMode = .signIn

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
                                    Text("👑 \(viewModel.userAccount.tier)")
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
                            }
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
                    .padding(.horizontal)

                    if viewModel.isProReviewDemo {
                        NavigationLink {
                            ProTeamReviewView(viewModel: viewModel)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.3.fill")
                                    .font(.title3)
                                    .foregroundStyle(.indigo)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Review team days")
                                        .font(.subheadline.weight(.semibold))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.indigo.opacity(0.09)))
                        }
                        .buttonStyle(.plain)
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
                                Picker("Cloud account action", selection: $authMode) {
                                    ForEach(CloudAuthMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)

                                TextField("Username", text: $newUsername)
                                    .modernTextInput()
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()

                                if authMode == .create {
                                    TextField("Email Address", text: $newEmail)
                                        .modernTextInput()
                                        .textInputAutocapitalization(.never)
                                        .keyboardType(.emailAddress)
                                }

                                SecureField("Password", text: $newPassword)
                                    .modernTextInput()

                                if !newPassword.isEmpty && newPassword.count < 8 {
                                    Text("Use at least 8 characters.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if let errorMessage = viewModel.errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                Button(authMode.rawValue) {
                                    if authMode == .create {
                                        guard !newUsername.isEmpty,
                                              !newEmail.isEmpty,
                                              !newPassword.isEmpty else { return }
                                        viewModel.registerAndSwitchAccount(
                                            username: newUsername,
                                            email: newEmail,
                                            password: newPassword
                                        )
                                    } else {
                                        viewModel.loginAndSwitchAccount(
                                            username: newUsername,
                                            password: newPassword
                                        )
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)
                                .disabled(
                                    viewModel.isLoading
                                        || newUsername.isEmpty
                                        || newPassword.count < 8
                                        || (authMode == .create && newEmail.isEmpty)
                                )
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
            guard viewModel.userAccount.isCloudSynced else { return }
            newUsername = ""
            newEmail = ""
            newPassword = ""
            showingAddForm = false
        }
    }

    private var accountStatusLabel: String {
        if viewModel.userAccount.isCloudSynced { return "☁️ Cloud Synced" }
        return viewModel.isProReviewDemo ? "👥 Local Pro Review" : "📱 Personal Workspace"
    }

    private var accountStatusColor: Color {
        if viewModel.userAccount.isCloudSynced { return .green }
        return viewModel.isProReviewDemo ? .indigo : .secondary
    }
}

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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(person.name).font(.subheadline.weight(.bold))
                        ForEach(viewModel.todos.filter { $0.assigneeId == person.id.uuidString && Calendar.current.isDateInToday($0.doDate) }.sorted { ($0.plannedStartTime ?? "23:59") < ($1.plannedStartTime ?? "23:59") }) { task in
                            VStack(alignment: .leading, spacing: 2) { Text(task.plannedStartTime ?? "Any time").font(.caption2.weight(.bold)); Text(task.title).font(.caption).lineLimit(2) }
                                .padding(8).frame(width: 145, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Color.indigo.opacity(0.13)))
                        }
                    }.frame(width: 165, alignment: .leading).padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
                }
            }
        }
    }
}

private struct TeamTaskReviewRow: View {
    let task: TodoEntry

    private var planned: String {
        guard let start = task.originalPlannedStartTime ?? task.plannedStartTime else { return "Unscheduled" }
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

struct AccountView_Previews: PreviewProvider {
    static var previews: some View { AccountView(viewModel: TodoViewModel()) }
}
