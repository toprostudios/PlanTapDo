import SwiftUI

struct CategoriesView: View {
    @ObservedObject var viewModel: TodoViewModel
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var showingAddCategory = false
    @State private var showingPremiumUpgrade = false
    @State private var selectedCategoryToEdit: Category?
    @State private var selectedTodo: TodoEntry?
    @AppStorage("tasksHubShowsAllTasks") private var showsAllTasks = true

    private var visibleTasks: [TodoEntry] {
        viewModel.todos.filter(viewModel.shouldDisplay).sorted { left, right in
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
                    }

                    Spacer()

                    Button {
                        if viewModel.canAddCategory(isPremium: subscriptionManager.hasPremium) {
                            showingAddCategory = true
                        } else {
                            showingPremiumUpgrade = true
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
                                $0.categoryId == category.id && viewModel.shouldDisplay($0)
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

                if showsAllTasks {
                    if visibleTasks.isEmpty {
                        Text("No tasks yet")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(visibleTasks) { todo in
                            TaskListRowView(
                                todo: todo,
                                category: category(for: todo.categoryId),
                                viewModel: viewModel,
                                onOpen: { selectedTodo = todo }
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $showingAddCategory) {
            AddCategoryView(viewModel: viewModel)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingPremiumUpgrade) {
            PremiumUpgradeView()
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
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.1)))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: category.colorHex))
                .frame(width: 5)
        }
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

    private var category: Category? {
        viewModel.categories.first { $0.id == categoryId }
    }

    private var categoryTodos: [TodoEntry] {
        viewModel.todos
            .filter { $0.categoryId == categoryId && viewModel.shouldDisplay($0) }
            .sorted {
                if !Calendar.current.isDate($0.doDate, inSameDayAs: $1.doDate) {
                    return $0.doDate < $1.doDate
                }
                let leftTime = $0.plannedStartTime ?? "23:59"
                let rightTime = $1.plannedStartTime ?? "23:59"
                if leftTime == rightTime {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return leftTime < rightTime
            }
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
                ForEach(categoryTodos) { todo in
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

                if categoryTodos.isEmpty {
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
    @State private var durationMinutes = 30
    @State private var recurrence: RecurrenceFrequency = .none
    @State private var selectedWeekdays = Set<Int>()
    @State private var notificationPreference: NotificationPreference?

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task title", text: $title)
                        .modernTextInput()
                    TextField("Notes (optional)", text: $description, axis: .vertical)
                        .lineLimit(2...4)
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
                    DatePicker("Day", selection: $scheduledDate, displayedComponents: .date)
                    Toggle("Set a time", isOn: $hasPlannedTime)

                    if hasPlannedTime {
                        DatePicker("Start", selection: $plannedTime, displayedComponents: .hourAndMinute)
                        HStack {
                            Text("Duration")
                            Spacer()
                            Picker("Duration", selection: $durationMinutes) {
                                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                                    Text(minutes < 60 ? "\(minutes) min" : "\(Double(minutes) / 60, specifier: "%.1g") hr")
                                        .tag(minutes)
                                }
                            }
                            .pickerStyle(.menu)
                        }
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
        dismiss()
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

    private let swatches = ["7C6FF7", "3ECF8E", "F5A623", "60A5FA", "EC4899", "F43F5E", "EAB308", "14B8A6"]

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
    @State private var showingPremiumLimit = false

    private let swatches = ["7C6FF7", "3ECF8E", "F5A623", "60A5FA", "EC4899", "F43F5E", "EAB308", "14B8A6"]

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
                            isPremium: subscriptionManager.hasPremium
                        ) else {
                            showingPremiumLimit = true
                            return
                        }
                        onSave(category)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Premium unlocks unlimited categories", isPresented: $showingPremiumLimit) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Free accounts can create up to \(TodoViewModel.freeCategoryLimit) categories.")
            }
        }
    }
}

private struct PremiumUpgradeView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.indigo)
                Text("PlanTapDo Premium")
                    .font(.title.weight(.bold))
                Text("Premium lets you create unlimited categories. More Premium features will be added over time.")
                    .foregroundStyle(.secondary)

                ForEach(SubscriptionManager.PremiumPlan.allCases) { plan in
                    Button {
                        Task {
                            await subscriptionManager.purchase(plan)
                            if subscriptionManager.hasPremium { dismiss() }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(plan.title).font(.headline)
                                Text(plan.fallbackPrice).font(.subheadline)
                            }
                            Spacer()
                            if subscriptionManager.isLoading { ProgressView() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(subscriptionManager.isLoading)
                }

                Button("Restore Purchases") {
                    Task {
                        await subscriptionManager.restorePurchases()
                        if subscriptionManager.hasPremium { dismiss() }
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(subscriptionManager.isLoading)

                if let errorMessage = subscriptionManager.errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Go Premium")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
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
    }
}
