import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "Settings"
    case offTime = "Off time"
    case reports = "Reports"

    var id: String { rawValue }
}

struct SettingsView: View {
    @ObservedObject var viewModel: TodoViewModel
    @State private var selectedSection: SettingsSection = .general

    private var privacyPolicyURL: URL? {
        configuredHTTPSURL(forInfoKey: "PRIVACY_POLICY_URL")
    }

    private var supportURL: URL? {
        configuredHTTPSURL(forInfoKey: "SUPPORT_URL")
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings section", selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedSection {
            case .general: generalSettings
            case .offTime: OffTimeSettingsView(viewModel: viewModel)
            case .reports: ReportsView(viewModel: viewModel)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var generalSettings: some View {
        Form {
            Section("✅ Task Visibility") {
                Toggle("Show completed tasks", isOn: $viewModel.showCompletedTasks)
            }

            Section("▶️ Running tasks") {
                Toggle("Start another task automatically", isOn: $viewModel.automaticallySwitchRunningTask)
                Text("When enabled, starting another task stops the current timer, keeps the recorded segment, and moves its unfinished time later in the schedule. When disabled, stop the current task first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("🎨 Appearance & Readability") {
                Picker("Theme", selection: $viewModel.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("ℹ️ About & Support") {
                if let privacyPolicyURL {
                    Link("Privacy Policy", destination: privacyPolicyURL)
                }
                if let supportURL {
                    Link("Support", destination: supportURL)
                }
                if privacyPolicyURL == nil || supportURL == nil {
                    Text("Privacy and support links must be configured in the release build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Version", value: versionLabel)
            }

        }
        .scrollContentBackground(.hidden)
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func configuredHTTPSURL(forInfoKey key: String) -> URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme?.lowercased() == "https",
            url.host != nil
        else { return nil }
        return url
    }
}

private struct OffTimeSettingsView: View {
    @ObservedObject var viewModel: TodoViewModel
    @State private var isEnabled = false
    @State private var start = 22 * 60
    @State private var end = 7 * 60

    var body: some View {
        Form {
            Section("Off time") {
                Toggle(isOn: $isEnabled) {
                    HStack {
                        Text("Hide tasks during off time")
                        Spacer()
                        if isEnabled {
                            Text("\(time(start)) – \(time(end))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("No tasks are scheduled during this time. It is useful for sleep or unavailable hours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isEnabled {
                    Picker("From", selection: $start) {
                        ForEach(Array(stride(from: 0, through: 23 * 60, by: 60)), id: \.self) { Text(time($0)).tag($0) }
                    }
                    Picker("Until", selection: $end) {
                        ForEach(Array(stride(from: 60, through: 24 * 60, by: 60)), id: \.self) { Text(time($0)).tag($0) }
                    }
                    Text("This repeats every day. It can span overnight, such as 10 PM to 7 AM.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .onAppear { load() }
        .onChange(of: isEnabled) { _ in save() }
        .onChange(of: start) { _ in save() }
        .onChange(of: end) { _ in save() }
    }

    private func time(_ minutes: Int) -> String {
        let normalized = minutes % (24 * 60)
        let hour = normalized / 60
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        return "\(displayHour):\(String(format: "%02d", normalized % 60)) \(period)"
    }

    private func load() {
        guard let block = viewModel.focusBlocks.first else { return }
        isEnabled = true
        if let morningSegment = viewModel.focusBlocks.first(where: { $0.startMinutes == 0 }) {
            start = block.startMinutes == 0
                ? (viewModel.focusBlocks.first(where: { $0.endMinutes == 24 * 60 })?.startMinutes ?? 22 * 60)
                : block.startMinutes
            end = morningSegment.endMinutes
        } else {
            start = block.startMinutes
            end = block.endMinutes
        }
    }

    private func save() {
        // The first release intentionally supports one global window only.
        // Category- and profile-specific off time belong on the post-v1 roadmap.
        viewModel.setOffTime(enabled: isEnabled, startMinutes: start, endMinutes: end)
    }
}

private struct ReportsView: View {
    @ObservedObject var viewModel: TodoViewModel
    @State private var selectedReport = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Report period", selection: $selectedReport) {
                Text("Daily").tag(0)
                Text("Weekly").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedReport == 0 {
                DailyReportsView(viewModel: viewModel)
            } else {
                WeeklyReportsView(viewModel: viewModel)
            }
        }
    }
}

private struct DailyReportsView: View {
    @ObservedObject var viewModel: TodoViewModel

    private var todayTodos: [TodoEntry] {
        viewModel.todos(on: Date())
    }

    private var trackedSeconds: TimeInterval {
        let calendar = Calendar.current
        return viewModel.todos.flatMap { $0.timeSessions ?? [] }
            .filter { calendar.isDate($0.start, inSameDayAs: Date()) }
            .reduce(0) { total, session in
                total + (session.duration ?? session.end.map { $0.timeIntervalSince(session.start) } ?? 0)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Daily report")
                    .font(.title3.weight(.bold))
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ReportMetricCard(title: "Completed", value: "\(todayTodos.filter { $0.status == .completed }.count)/\(todayTodos.count)", icon: "checkmark.circle.fill", color: .green)
                    ReportMetricCard(title: "Planned", value: String(format: "%.1fh", todayTodos.reduce(0) { $0 + $1.plannedDuration } / 3_600), icon: "calendar", color: .indigo)
                    ReportMetricCard(title: "Tracked", value: String(format: "%.1fh", trackedSeconds / 3_600), icon: "timer", color: .orange)
                }
            }
            .padding()
        }
    }
}

private struct WeeklyReportsView: View {
    @ObservedObject var viewModel: TodoViewModel
    @State private var weekOffset = 0

    private var interval: DateInterval {
        let calendar = Calendar.current
        let anchor = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date()) ?? Date()
        return calendar.dateInterval(of: .weekOfYear, for: anchor)
            ?? DateInterval(start: calendar.startOfDay(for: anchor), duration: 7 * 86_400)
    }

    private var weekTodos: [TodoEntry] {
        viewModel.todos.filter { interval.contains($0.doDate) }
    }

    private var completedTodos: [TodoEntry] {
        weekTodos.filter { $0.status == .completed }
    }

    private var plannedHours: Double {
        weekTodos.reduce(0) { $0 + $1.plannedDuration } / 3_600
    }

    private var trackedHours: Double {
        viewModel.todos.flatMap { $0.timeSessions ?? [] }
            .filter { interval.contains($0.start) }
            .reduce(0) { partial, session in
                partial + (session.duration ?? session.end.map { $0.timeIntervalSince(session.start) } ?? 0)
            } / 3_600
    }

    private var dailyCompletion: [(day: Date, completed: Int, total: Int)] {
        let calendar = Calendar.current
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let tasks = weekTodos.filter { calendar.isDate($0.doDate, inSameDayAs: day) }
            return (day, tasks.filter { $0.status == .completed }.count, tasks.count)
        }
    }

    var body: some View {
        personalReport
    }

    private var personalReport: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                HStack {
                    Button { weekOffset -= 1 } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 40, height: 40)
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text("Weekly report")
                            .font(.headline)
                        Text("\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(interval.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button { weekOffset += 1 } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 40, height: 40)
                    }
                    .disabled(weekOffset >= 0)
                }
                .padding(.horizontal)

                HStack(spacing: 10) {
                    ReportMetricCard(
                        title: "Completed",
                        value: "\(completedTodos.count)/\(weekTodos.count)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    ReportMetricCard(
                        title: "Planned",
                        value: String(format: "%.1fh", plannedHours),
                        icon: "calendar",
                        color: .indigo
                    )
                    ReportMetricCard(
                        title: "Actual",
                        value: String(format: "%.1fh", trackedHours),
                        icon: "timer",
                        color: .orange
                    )
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Completed tasks by day")
                        .font(.headline)
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(dailyCompletion, id: \.day) { item in
                            VStack(spacing: 5) {
                                Text("\(item.completed)")
                                    .font(.caption2.weight(.bold))
                                GeometryReader { geo in
                                    let maxCount = max(1, dailyCompletion.map(\.total).max() ?? 1)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.indigo)
                                        .frame(height: max(3, geo.size.height * CGFloat(item.completed) / CGFloat(maxCount)), alignment: .bottom)
                                        .frame(maxHeight: .infinity, alignment: .bottom)
                                }
                                .frame(height: 64)
                                Text(item.day.formatted(.dateTime.weekday(.narrow)))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("\(item.day.formatted(.dateTime.weekday(.wide))): \(item.completed) of \(item.total) tasks completed")
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.1)))
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Completion by category")
                        .font(.headline)

                    ForEach(viewModel.categories) { category in
                        let tasks = weekTodos.filter { $0.categoryId == category.id }
                        if !tasks.isEmpty {
                            let completed = tasks.filter { $0.status == .completed }.count
                            let progress = Double(completed) / Double(tasks.count)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(category.icon ?? "🔖") \(category.name)")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(completed)/\(tasks.count)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: progress)
                                    .tint(Color(hex: category.colorHex))
                            }
                        }
                    }

                    if weekTodos.isEmpty {
                        Text("No tasks were scheduled for this week.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.1)))
                .padding(.horizontal)
            }
            .padding(.bottom, 28)
        }
    }
}

#if TEAM_VIEW_ENABLED
// Deactivated: preserved outside active Team feature builds.
private struct TeamWeeklyReportView: View {
    @ObservedObject var viewModel: TodoViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Team members")
                    .font(.headline)
                Text("This week’s planned and completed tasks, per person.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.teamReviewPeople) { person in
                    let tasks = viewModel.todos.filter { $0.assigneeId == person.id.uuidString }
                    let completed = tasks.filter { $0.status == .completed }.count
                    HStack(spacing: 12) {
                        Circle().fill(Color.indigo).frame(width: 38, height: 38)
                            .overlay(Text(person.name.prefix(1)).foregroundStyle(.white).fontWeight(.bold))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(person.name).font(.subheadline.weight(.bold))
                            Text("\(completed) completed · \(tasks.count) planned")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProgressView(value: tasks.isEmpty ? 0 : Double(completed) / Double(tasks.count))
                            .frame(width: 72).tint(.indigo)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.1)))
                }
            }
            .padding()
        }
    }
}
#endif

private struct ReportMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.1)))
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView(viewModel: TodoViewModel())
        }
    }
}
