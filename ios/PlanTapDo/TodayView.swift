// TodayView.swift
import SwiftUI

struct TodayView: View {
    @ObservedObject var viewModel: TodoViewModel

    @State private var selectedTodo: TodoEntry?
    @State private var showingTaskComposer = false

    private var todayTodos: [TodoEntry] {
        viewModel.todos(on: Date())
    }

    private func overdueLabel(for todo: TodoEntry) -> String? {
        guard let overdueDate = todo.overdueFromDate else { return nil }
        return "OVERDUE · " + overdueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func category(for categoryId: UUID?) -> Category? {
        guard let categoryId else { return nil }
        return viewModel.categories.first { $0.id == categoryId }
    }

    var body: some View {
        Group {
            if viewModel.displayStyle == .list {
                ScreenContainer(maxWidth: 600) {
                    VStack(spacing: 12) {
                        pageHeader
                        layoutPicker
                        LazyVStack(spacing: 6) {
                            ForEach(todayTodos) { todo in
                                TaskListRowView(
                                    todo: todo,
                                    category: category(for: todo.categoryId),
                                    viewModel: viewModel,
                                    overdueLabel: overdueLabel(for: todo),
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
                        onOpenTask: { selectedTodo = $0 }
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
            TaskComposerView(viewModel: viewModel, start: Date(), showsSchedule: false)
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

    private var isTimerActive: Bool {
        viewModel.activeTimerTodoId == todo.id
    }

    var body: some View {
        HStack(spacing: 9) {
            Button {
                viewModel.toggleComplete(todo)
            } label: {
                Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.status == .completed ? .green : .secondary)
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
                        Text("\(plannedStartTime) · \(Int(todo.plannedDuration / 60)) min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let overdueLabel {
                        Text(overdueLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }
                .frame(minWidth: 0, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if todo.status != .completed {
                Button {
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
                .accessibilityLabel(isTimerActive ? "Stop \(todo.title)" : "Start \(todo.title)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.15)))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(categoryColor)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, usesOuterPadding ? 16 : 0)
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
                    if let overdueDate = todo.overdueFromDate {
                        LabeledContent("Overdue") {
                            Text(overdueDate.formatted(date: .long, time: .omitted))
                                .foregroundStyle(.red)
                        }
                    }
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

                Section("Organization") {
                    Picker("Category", selection: $categoryId) {
                        Text("No Category").tag(UUID?.none)
                        ForEach(viewModel.categories) { category in
                            Text("\(category.icon ?? "🔖") \(category.name)")
                                .tag(Optional(category.id))
                        }
                    }
                }
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
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
