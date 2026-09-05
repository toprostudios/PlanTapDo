import SwiftUI

struct CategoriesView: View {
    @ObservedObject var viewModel: TodoViewModel
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var showingAddCategory = false
    @State private var showingAdvancedUpgrade = false
    @State private var selectedCategoryToEdit: Category?
    @State private var selectedTodo: TodoEntry?
    @AppStorage("tasksHubShowsAllTasks") private var showsAllTasks = true

    private var activeTasks: [TodoEntry] {
        sortedTasks(viewModel.todos.filter {
            $0.status != .completed && $0.status != .archived && $0.status != .skipped
                && viewModel.shouldDisplayInList($0)
        })
    }

    private var completedTasks: [TodoEntry] {
        guard viewModel.showCompletedTasks else { return [] }
        return sortedTasks(viewModel.todos.filter {
            $0.status == .completed && viewModel.shouldDisplayInList($0)
        })
    }

    private func sortedTasks(_ tasks: [TodoEntry]) -> [TodoEntry] {
        tasks.sorted { left, right in
            if (left.categoryId == nil) != (right.categoryId == nil) { return left.categoryId == nil }
            if !Calendar.current.isDate(left.doDate, inSameDayAs: right.doDate) { return left.doDate < right.doDate }
            let leftTime = left.plannedStartTime ?? "00:00"
            let rightTime = right.plannedStartTime ?? "00:00"
            if leftTime != rightTime { return leftTime < rightTime }
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    private func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return viewModel.categories.first { $0.id == id }
    }

    var body: some View {
        ScreenContainer(maxWidth: 700) {
            LazyVStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your categories")
                            .font(.title3.weight(.bold))
                        if !subscriptionManager.hasAdvanced {
                            Text("Free: \(TodoViewModel.freeCategoryLimit) categories")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        AppHaptics.impact(.medium)
                        if viewModel.canAddCategory(isAdvanced: subscriptionManager.hasAdvanced) {
                            showingAddCategory = true
                        } else {
                            showingAdvancedUpgrade = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.indigo))
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Add category")
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ForEach(viewModel.categories) { category in
                    NavigationLink {
                        CategoryDetailView(viewModel: viewModel, categoryId: category.id)
                    } label: {
                        CategoryRow(
                            category: category,
                            taskCount: viewModel.todos.filter {
                            $0.categoryId == category.id && $0.status != .completed
                                && $0.status != .archived && $0.status != .skipped
                                && viewModel.shouldDisplayInList($0)
                            }.count
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                    .contextMenu {
                        Button {
                            selectedCategoryToEdit = category
                        } label: {
                            Label("Edit Category", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            viewModel.deleteCategory(id: category.id)
                        } label: {
                            Label("Delete Category", systemImage: "trash")
                        }
                    }
                }

                if viewModel.categories.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.largeTitle)
                        Text("No Categories")
                            .font(.headline)
                    }
                    .padding(.top, 50)
                }

                Divider().padding(.horizontal)

                Button { showsAllTasks.toggle() } label: {
                    HStack {
                        Text("Tasks")
                            .font(.title3.weight(.bold))
                        Spacer()
                        Image(systemName: showsAllTasks ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
                .tactilePress()
                .simultaneousGesture(TapGesture().onEnded { AppHaptics.selection() })

                if showsAllTasks {
                    if activeTasks.isEmpty {
                        Text("No tasks yet")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(activeTasks) { todo in
                            TaskListRowView(
                                todo: todo,
                                category: category(for: todo.categoryId),
                                viewModel: viewModel,
                                onOpen: { selectedTodo = todo },
                                usesOuterPadding: false
                            )
                            .padding(.horizontal, 16)
                        }
                    }

                    CompletedTaskListSection(
                        todos: completedTasks,
                        viewModel: viewModel,
                        categoryFor: category,
                        onOpen: { selectedTodo = $0 },
                        usesOuterPadding: false
                    )
                    .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategoryView(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingAdvancedUpgrade) {
            AdvancedUpgradeView()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedCategoryToEdit) { category in
            EditCategoryView(viewModel: viewModel, category: category)
                .presentationDetents([.medium])
        }
        .sheet(item: $selectedTodo) { todo in
            TaskDetailView(todo: todo, viewModel: viewModel)
        }
    }
}

private struct CategoryRow: View {
    let category: Category
    let taskCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Text(category.icon ?? "🔖")
                .font(.title2)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: category.colorHex).opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.body.weight(.bold))
                Text("\(taskCount) active task\(taskCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(hex: category.colorHex))
                .rotationEffect(.degrees(-90))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: category.colorHex).opacity(0.15),
                            Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: category.colorHex))
                .frame(width: 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: category.colorHex).opacity(0.12), radius: 10, y: 4)
    }
}

struct CategoryDetailView: View {
    @ObservedObject var viewModel: TodoViewModel
    let categoryId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var showingTaskComposer = false
    @State private var showingEditCategory = false
    @State private var showingDeleteConfirmation = false
    @State private var selectedTodo: TodoEntry?
    @State private var completedTasksExpanded = false

    private var category: Category? {
        viewModel.categories.first { $0.id == categoryId }
    }

    private var activeCategoryTodos: [TodoEntry] {
        viewModel.todos
            .filter {
                $0.categoryId == categoryId
                    && $0.status != .completed
                    && $0.status != .archived
                    && $0.status != .skipped
                    && viewModel.shouldDisplayInList($0)
            }
            .sorted(by: taskSort)
    }

    private var completedCategoryTodos: [TodoEntry] {
        guard viewModel.showCompletedTasks else { return [] }
        return viewModel.todos
            .filter {
                $0.categoryId == categoryId
                    && $0.status == .completed
                    && viewModel.shouldDisplayInList($0)
            }
            .sorted(by: taskSort)
    }

    private func taskSort(_ left: TodoEntry, _ right: TodoEntry) -> Bool {
        if !Calendar.current.isDate(left.doDate, inSameDayAs: right.doDate) {
            return left.doDate < right.doDate
        }
        let leftTime = left.plannedStartTime ?? "23:59"
        let rightTime = right.plannedStartTime ?? "23:59"
        if leftTime == rightTime {
            return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
        return leftTime < rightTime
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingTaskComposer = true
                } label: {
                    Label("Add a task", systemImage: "plus.circle.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color(hex: category?.colorHex ?? "7C6FF7"))
                }
            }

            Section("Tasks") {
                ForEach(activeCategoryTodos) { todo in
                    TaskListRowView(
                        todo: todo,
                        category: category,
                        viewModel: viewModel,
                        onOpen: { selectedTodo = todo },
                        usesOuterPadding: false
                    )
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if activeCategoryTodos.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No active tasks in this category")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .listRowBackground(Color.clear)
                }
            }

            if !completedCategoryTodos.isEmpty {
                Section {
                    DisclosureGroup(
                        "Completed (\(completedCategoryTodos.count))",
                        isExpanded: $completedTasksExpanded
                    ) {
                        ForEach(completedCategoryTodos) { todo in
                            TaskListRowView(
                                todo: todo,
                                category: category,
                                viewModel: viewModel,
                                onOpen: { selectedTodo = todo },
                                usesOuterPadding: false
                            )
                            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .tint(.green)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("\(category?.icon ?? "🔖") \(category?.name ?? "Category")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditCategory = true
                    } label: {
                        Label("Edit Category", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Category", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .confirmationDialog(
            "Delete \"\(category?.name ?? "Category")\"?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Category", role: .destructive) {
                viewModel.deleteCategory(id: categoryId)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Tasks in this category will not be deleted, but will become uncategorized.")
        }
        .sheet(isPresented: $showingEditCategory) {
            if let category {
                EditCategoryView(viewModel: viewModel, category: category)
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showingTaskComposer) {
            CategoryTaskComposerView(viewModel: viewModel, categoryId: categoryId)
                .presentationDetents([.large])
        }
        .sheet(item: $selectedTodo) { todo in
            TaskDetailView(todo: todo, viewModel: viewModel)
        }
    }
}

private struct CategoryTaskComposerView: View {
    @ObservedObject var viewModel: TodoViewModel
    let categoryId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var scheduledDate = Date()
    @State private var hasPlannedTime = true
    @State private var plannedTime = Date()
    @State private var durationMinutes = 5
    @State private var recurrence: RecurrenceFrequency = .none
    @State private var selectedWeekdays = Set<Int>()
    @State private var notificationPreference: NotificationPreference?
    @State private var showingCustomDuration = false
    @State private var customDurationText = "5"

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task title", text: $title, axis: .vertical)
                        .lineLimit(1...2)
                        .modernTextInput()
                    TextField("Notes (optional)", text: $description, axis: .vertical)
                        .lineLimit(1...5)
                        .modernTextInput()
                }

                if hasPlannedTime {
                    Section("Notification") {
                        NotificationPreferencePicker(
                            preference: $notificationPreference,
                            inheritedPreference: viewModel.categories.first { $0.id == categoryId }?.notificationPreference,
                            allowsInheritedDefault: true
                        )
                    }
                }

                Section("Schedule") {
                    RelativeDayWheelPicker(date: $scheduledDate)
                    Toggle("Set a time", isOn: $hasPlannedTime)

                    if hasPlannedTime {
                        FiveMinuteTimePicker(date: $plannedTime)
                    }
                    Picker("Duration", selection: $durationMinutes) {
                        Text("Unspecified (5 min estimate)").tag(0)
                        ForEach(durationChoices, id: \.self) { minutes in
                            Text(durationLabel(minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 118)
                    .clipped()
                    Button("Custom duration") {
                        customDurationText = String(durationMinutes)
                        showingCustomDuration = true
                    }
                    if durationMinutes == 0 {
                        Text("Unspecified tasks stay in the list and do not appear on the calendar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Repeat") {
                    Picker("Repeat", selection: $recurrence) {
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.label).tag(frequency)
                        }
                    }
                    if recurrence == .custom {
                        WeekdaySelector(selectedWeekdays: $selectedWeekdays)
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addTask)
                        .fontWeight(.bold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingCustomDuration) {
            NavigationStack {
                Form {
                    Section("Minutes") {
                        TextField("Minutes", text: $customDurationText)
                            .keyboardType(.numberPad)
                    }
                    Text("Choose any duration from 1 minute to 24 hours.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .navigationTitle("Custom duration")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingCustomDuration = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Set") {
                            durationMinutes = min(24 * 60, max(1, Int(customDurationText) ?? durationMinutes))
                            showingCustomDuration = false
                        }
                    }
                }
            }
            .presentationDetents([.fraction(0.3)])
        }
    }

    private func addTask() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        viewModel.createTodo(
            title: trimmedTitle,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : description,
            doDate: scheduledDate,
            dueDate: nil,
            plannedStartTime: hasPlannedTime ? TodoEntry.apiTimeString(from: plannedTime) : nil,
            plannedDuration: TimeInterval(durationMinutes * 60),
            categoryId: categoryId,
            notificationPreference: notificationPreference,
            recurrenceFrequency: recurrence,
            recurrenceWeekdays: recurrence == .custom
                ? Array(
                    selectedWeekdays.isEmpty
                        ? [Calendar.autoupdatingCurrent.component(.weekday, from: scheduledDate)]
                        : selectedWeekdays
                ).sorted()
                : nil
        )
        AppHaptics.success()
        viewModel.showTaskAddedFeedback(for: trimmedTitle)
        dismiss()
    }


    private var durationChoices: [Int] {
        [5, 15, 30] + Array(stride(from: 60, through: 24 * 60, by: 30))
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }
}

private struct EditCategoryView: View {
    @ObservedObject var viewModel: TodoViewModel
    let category: Category
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var colorHex: String
    @State private var notificationPreference: NotificationPreference?

    // Green is reserved for tasks with a running timer.
    private let swatches = ["7C6FF7", "F5A623", "60A5FA", "EC4899", "F43F5E", "EAB308", "14B8A6"]

    init(viewModel: TodoViewModel, category: Category) {
        self.viewModel = viewModel
        self.category = category
        _name = State(initialValue: category.name)
        _icon = State(initialValue: category.icon ?? "🔖")
        _colorHex = State(initialValue: category.colorHex)
        _notificationPreference = State(initialValue: category.notificationPreference)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name", text: $name)
                        .modernTextInput()
                    TextField("Any emoji", text: $icon)
                        .font(.title2)
                        .modernTextInput()
                        .accessibilityLabel("Category emoji")

                    Text("Quick picks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(["🎯", "💼", "🏡", "🏋️", "📚", "🎨", "🧠", "🛒", "✈️", "🎵", "💰", "❤️"], id: \.self) { emoji in
                            Button { icon = emoji } label: {
                                Text(emoji).font(.title3).frame(width: 34, height: 34)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(icon == emoji ? Color.indigo.opacity(0.2) : Color.clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Calendar color") {
                    HStack(spacing: 12) {
                        ForEach(swatches, id: \.self) { swatch in
                            Button {
                                colorHex = swatch
                            } label: {
                                Circle()
                                    .fill(Color(hex: swatch))
                                    .frame(width: 27, height: 27)
                                    .overlay {
                                        if colorHex == swatch {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.black))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Default notifications") {
                    NotificationPreferencePicker(
                        preference: $notificationPreference,
                        inheritedPreference: nil,
                        allowsInheritedDefault: false
                    )
                    Text("Applies to timed tasks in this category unless a task has its own notification setting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = category
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.icon = icon.isEmpty ? "🔖" : icon
                        updated.colorHex = colorHex
                        updated.notificationPreference = notificationPreference ?? .none
                        viewModel.updateCategory(updated)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct AddCategoryView: View {
    @ObservedObject var viewModel: TodoViewModel
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    var onSave: (Category) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "🎯"
    @State private var colorHex = "7C6FF7"
    @State private var showingAdvancedLimit = false

    // Green is reserved for tasks with a running timer.
    private let swatches = ["7C6FF7", "F5A623", "60A5FA", "EC4899", "F43F5E", "EAB308", "14B8A6"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name", text: $name)
                        .modernTextInput()
                    TextField("Any emoji", text: $icon)
                        .font(.title2)
                        .modernTextInput()
                        .accessibilityLabel("Category emoji")

                    Text("Quick picks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(["🎯", "💼", "🏡", "🏋️", "📚", "🎨", "🧠", "🛒", "✈️", "🎵", "💰", "❤️"], id: \.self) { emoji in
                            Button { icon = emoji } label: {
                                Text(emoji).font(.title3).frame(width: 34, height: 34)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(icon == emoji ? Color.indigo.opacity(0.2) : Color.clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Calendar color") {
                    HStack(spacing: 12) {
                        ForEach(swatches, id: \.self) { swatch in
                            Button {
                                colorHex = swatch
                            } label: {
                                Circle()
                                    .fill(Color(hex: swatch))
                                    .frame(width: 27, height: 27)
                                    .overlay {
                                        if colorHex == swatch {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.black))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let category = viewModel.addCategory(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            colorHex: colorHex,
                            icon: icon.isEmpty ? "🔖" : icon,
                            isAdvanced: subscriptionManager.hasAdvanced
                        ) else {
                            showingAdvancedLimit = true
                            return
                        }
                        onSave(category)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Advanced unlocks unlimited categories", isPresented: $showingAdvancedLimit) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Free accounts can create up to \(TodoViewModel.freeCategoryLimit) categories.")
            }
        }
    }
}

struct AdvancedUpgradeView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    private var privacyPolicyURL: URL? {
        configuredHTTPSURL(forInfoKey: "PRIVACY_POLICY_URL")
    }

    private var termsOfUseURL: URL? {
        configuredHTTPSURL(forInfoKey: "TERMS_OF_USE_URL")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 54)
                            .background(Circle().fill(Color.indigo.gradient))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Unlimited Categories")
                                .font(.title2.weight(.bold))
                            Text("PlanTapDo Advanced")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.indigo)
                        }
                    }

                    Text("CURRENT PLAN")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: subscriptionManager.hasAdvanced ? "checkmark.seal.fill" : "person.crop.circle")
                                .foregroundStyle(subscriptionManager.hasAdvanced ? .green : .secondary)
                            Text(subscriptionManager.hasAdvanced ? "Advanced" : "Free")
                                .font(.headline)
                            Spacer()
                            Text(subscriptionManager.hasAdvanced
                                ? "Unlimited access"
                                : "\(TodoViewModel.freeCategoryLimit) categories")
                                .foregroundStyle(.secondary)
                        }
                        if let activePlan = subscriptionManager.activePlan {
                            Text("\(activePlan.title) · \(activePlan.billingDescription)")
                                .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.indigo.opacity(0.09))
                    )

                    Text("WHAT YOU UNLOCK WITH ADVANCED")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Free")
                                .font(.headline)
                            Label("\(TodoViewModel.freeCategoryLimit) categories", systemImage: "folder")
                                .font(.caption)
                            Label("\(TodoViewModel.freeCategoryLimit) customized categories", systemImage: "paintpalette")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.secondary.opacity(0.10)))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Advanced")
                                .font(.headline)
                            Label("Unlimited categories", systemImage: "folder.badge.plus")
                                .font(.caption)
                            Label("Unlimited category customization", systemImage: "paintpalette.fill")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(.indigo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.indigo.opacity(0.10)))
                    }

                    if subscriptionManager.hasAdvanced {
                        Label("Advanced is active", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        Text("Upgrade your plan")
                            .font(.headline)

                        ForEach(SubscriptionManager.AdvancedPlan.allCases) { plan in
                            Button {
                                Task {
                                    await subscriptionManager.purchase(plan)
                                    if subscriptionManager.hasAdvanced { dismiss() }
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Advanced \(plan.title)")
                                            .font(.headline)
                                        Text(plan.billingDescription)
                                            .font(.subheadline)
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    Spacer()
                                    if subscriptionManager.isLoading {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text(subscriptionManager.displayPrice(for: plan))
                                            .font(.headline.weight(.bold))
                                    }
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.indigo)
                                )
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .disabled(subscriptionManager.isLoading || !subscriptionManager.isAvailable(for: plan))
                            .opacity(subscriptionManager.isAvailable(for: plan) ? 1 : 0.45)
                        }
                    }

                    Button("Restore Purchases") {
                        Task {
                            await subscriptionManager.restorePurchases()
                            if subscriptionManager.hasAdvanced { dismiss() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(subscriptionManager.isLoading)

                    if let errorMessage = subscriptionManager.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Payment is charged to your Apple Account at confirmation. Plans renew automatically unless cancelled at least 24 hours before the current period ends.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        if let termsOfUseURL {
                            Link("Terms", destination: termsOfUseURL)
                        }
                        if let privacyPolicyURL {
                            Link("Privacy", destination: privacyPolicyURL)
                        }
                        Link("Manage", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    }
                    .font(.footnote)
                }
                .padding(24)
            }
            .navigationTitle("Go Advanced")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
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

struct WeekdaySelector: View {
    @Binding var selectedWeekdays: Set<Int>
    private let days = [(1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")]
    var body: some View {
        HStack {
            ForEach(days, id: \.0) { day in
                Button(day.1) {
                    if selectedWeekdays.contains(day.0) { selectedWeekdays.remove(day.0) } else { selectedWeekdays.insert(day.0) }
                }
                .buttonStyle(.bordered)
                .tint(selectedWeekdays.contains(day.0) ? .indigo : .gray)
            }
        }
    }
}

struct CategoriesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CategoriesView(viewModel: TodoViewModel())
        }
        .environmentObject(SubscriptionManager())
    }
}
