// TodayView.swift
import SwiftUI

struct TodayView: View {
    @ObservedObject var viewModel: TodoViewModel

    @State private var selectedTodo: TodoEntry?
    @State private var showingTaskComposer = false

    private var todayTodos: [TodoEntry] {
        viewModel.todos(on: Date())
    }

    private func category(for categoryId: UUID?) -> Category? {
        guard let categoryId else { return nil }
        return viewModel.categories.first { $0.id == categoryId }
    }

    var body: some View {
        Group {
            if viewModel.displayStyle == .list {
                ScreenContainer(maxWidth: .infinity) {
                    VStack(spacing: 12) {
                        pageHeader
                        layoutPicker
                        LazyVStack(spacing: 6) {
                            ForEach(todayTodos) { todo in
                                TaskListRowView(
                                    todo: todo,
                                    category: category(for: todo.categoryId),
                                    viewModel: viewModel,
                                    onOpen: { selectedTodo = todo }
                                )
                            }

                            if todayTodos.isEmpty {
                                VStack(spacing: 8) {
                                    Text("🎉 All clear for Today!")
                                        .font(.headline)
                                }
                                .padding(40)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    pageHeader
                    layoutPicker
                    CalendarHourlyGrid(
                        viewModel: viewModel,
                        date: Date(),
                        onOpenTask: { selectedTodo = $0 },
                        allowsRangeSelection: false
                    )
                }
                .padding(.top, 4)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .sheet(item: $selectedTodo) { todo in
            TaskDetailView(todo: todo, viewModel: viewModel)
        }
        .sheet(isPresented: $showingTaskComposer) {
            TaskComposerView(viewModel: viewModel, start: Date())
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .bottomTrailing) {
            if viewModel.displayStyle == .list {
                Button { showingTaskComposer = true } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.indigo))
                        .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                }
                .tactilePress()
                .accessibilityLabel("Add task for now")
                .padding(.trailing, 22)
                .padding(.bottom, 18)
            }
        }
    }

    private var layoutPicker: some View {
        Picker("Layout", selection: $viewModel.displayStyle) {
            Text("List 📝").tag(DisplayStyle.list)
            Text("Calendar 🗓️").tag(DisplayStyle.calendar)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 4)
        .onChange(of: viewModel.displayStyle) { _ in AppHaptics.selection() }
    }

    private var pageHeader: some View {
        Text("Today")
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

}

struct TaskListRowView: View {
    let todo: TodoEntry
    let category: Category?
    @ObservedObject var viewModel: TodoViewModel
    var overdueLabel: String? = nil
    let onOpen: () -> Void
    var usesOuterPadding: Bool = true

    private var categoryColor: Color {
        Color(hex: category?.colorHex ?? "7C6FF7")
    }

    private var taskColor: Color {
        isTimerActive ? .green : categoryColor
    }

    private var isTimerActive: Bool {
        viewModel.activeTimerTodoId == todo.id
    }

    var body: some View {
        HStack(spacing: 9) {
            Button {
                AppHaptics.success()
                viewModel.toggleComplete(todo)
            } label: {
                Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(todo.status == .completed ? .white : taskColor)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(todo.status == .completed ? Color.green : taskColor.opacity(0.12)))
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(todo.title)
                            .font(.subheadline)
                            .strikethrough(todo.status == .completed)
                            .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                            .lineLimit(1)

                        if let icon = category?.icon {
                            Text(icon)
                                .font(.caption)
                        }
                    }

                    if let plannedStartTime = todo.plannedStartTime, !plannedStartTime.isEmpty {
                        Label("\(plannedStartTime) · \(Int(todo.plannedDuration / 60)) min", systemImage: "clock")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if let overdueLabel {
                        Text(overdueLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if todo.status != .completed {
                Button {
                    AppHaptics.impact(.medium)
                    if isTimerActive {
                        viewModel.stopTimer()
                    } else {
                        viewModel.startTimer(for: todo)
                    }
                } label: {
                    Image(systemName: isTimerActive ? "stop.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isTimerActive ? Color.red : Color.indigo))
                }
                .buttonStyle(.plain)
                .tactilePress()
                .accessibilityLabel(isTimerActive ? "Stop \(todo.title)" : "Start \(todo.title)")
                .disabled(!isTimerActive && !viewModel.canStartAnotherTask)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.thinMaterial))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(taskColor)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.045), radius: 8, y: 3)
        .padding(.horizontal, usesOuterPadding ? 16 : 0)
        .contextMenu {
            Button(action: onOpen) {
                Label("Edit Details", systemImage: "pencil")
            }

            Button {
                viewModel.duplicateTodo(todo)
            } label: {
                Label("Duplicate Task", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                viewModel.deleteTodo(id: todo.id)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }
}

struct TaskDetailView: View {
    let todo: TodoEntry
    @ObservedObject var viewModel: TodoViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var doDate: Date
    @State private var hasPlannedTime: Bool
    @State private var plannedTime: Date
    @State private var durationMinutes: Int
    @State private var categoryId: UUID?
    @State private var recurrenceFrequency: RecurrenceFrequency
    @State private var recurrenceWeekdays: Set<Int>
    @State private var notificationPreference: NotificationPreference?
    @State private var showingDeleteConfirmation = false

    init(todo: TodoEntry, viewModel: TodoViewModel) {
        self.todo = todo
        self.viewModel = viewModel
        _title = State(initialValue: todo.title)
        _description = State(initialValue: todo.description ?? "")
        _doDate = State(initialValue: todo.doDate)
        _hasPlannedTime = State(initialValue: todo.plannedStartTime != nil)
        _plannedTime = State(initialValue: Self.date(from: todo.plannedStartTime) ?? Date())
        _durationMinutes = State(initialValue: max(15, Int(todo.plannedDuration / 60)))
        _categoryId = State(initialValue: todo.categoryId)
        _recurrenceFrequency = State(initialValue: todo.recurrenceFrequency)
        _recurrenceWeekdays = State(initialValue: Set(todo.recurrenceWeekdays ?? []))
        _notificationPreference = State(initialValue: todo.notificationPreference)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task title", text: $title)
                        .modernTextInput()

                    TextEditor(text: $description)
                        .modernTextEditor(minHeight: 140)
                        .overlay(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("Add a description or notes")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section("Schedule") {
                    DatePicker("Day", selection: $doDate, displayedComponents: .date)
                    Toggle("Set a time", isOn: $hasPlannedTime)

                    if hasPlannedTime {
                        DatePicker("Start", selection: $plannedTime, displayedComponents: .hourAndMinute)
                        Picker("Duration", selection: $durationMinutes) {
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                            Text("45 min").tag(45)
                            Text("1 hour").tag(60)
                            Text("1.5 hours").tag(90)
                            Text("2 hours").tag(120)
                        }
                    }

                    Picker("Repeat", selection: $recurrenceFrequency) {
                        ForEach(RecurrenceFrequency.allCases) { frequency in
                            Text(frequency.label).tag(frequency)
                        }
                    }
                    if recurrenceFrequency == .custom {
                        WeekdaySelector(selectedWeekdays: $recurrenceWeekdays)
                    }
                }

                if hasPlannedTime {
                    Section("Notification") {
                        NotificationPreferencePicker(
                            preference: $notificationPreference,
                            inheritedPreference: categoryId.flatMap { id in viewModel.categories.first { $0.id == id }?.notificationPreference },
                            allowsInheritedDefault: true
                        )
                        Text("A notification is scheduled only when this task has a start time.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Organization") {
                    Picker("Category", selection: $categoryId) {
                        Text("No Category").tag(UUID?.none)
                        ForEach(viewModel.categories) { category in
                            Text("\(category.icon ?? "🔖") \(category.name)")
                                .tag(Optional(category.id))
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Task", systemImage: "trash")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Delete \"\(todo.title)\"?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Task", role: .destructive) {
                    viewModel.deleteTodo(id: todo.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.bold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        var updatedTodo = todo
        updatedTodo.title = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedTodo.description = trimmedDescription.isEmpty ? nil : trimmedDescription
        updatedTodo.doDate = doDate
        updatedTodo.plannedStartTime = hasPlannedTime ? TodoEntry.apiTimeString(from: plannedTime) : nil
        updatedTodo.plannedDuration = TimeInterval(durationMinutes * 60)
        updatedTodo.categoryId = categoryId
        updatedTodo.notificationPreference = notificationPreference
        updatedTodo.recurrenceFrequency = recurrenceFrequency
        if recurrenceFrequency == .custom {
            let fallbackWeekday = Calendar.autoupdatingCurrent.component(.weekday, from: doDate)
            updatedTodo.recurrenceWeekdays = Array(
                recurrenceWeekdays.isEmpty ? [fallbackWeekday] : recurrenceWeekdays
            ).sorted()
        } else {
            updatedTodo.recurrenceWeekdays = nil
        }
        if recurrenceFrequency == .none {
            updatedTodo.recurrenceSeriesId = nil
        }

        viewModel.updateTodo(updatedTodo)
        dismiss()
    }

    private static func date(from time: String?) -> Date? {
        guard let time else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date())
    }
}

struct TodayView_Previews: PreviewProvider {
    static var previews: some View { TodayView(viewModel: TodoViewModel()) }
}
