// TodayView.swift
import SwiftUI

struct TodayView: View {
    @ObservedObject var viewModel: TodoViewModel

    @State private var newTodoTitle = ""
    @State private var selectedTodo: TodoEntry?

    private var todayTodos: [TodoEntry] {
        viewModel.todos
            .filter { Calendar.current.isDateInToday($0.doDate) }
            .sorted { ($0.plannedStartTime ?? "23:59") < ($1.plannedStartTime ?? "23:59") }
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
                        layoutPicker
                        quickAddBar

                        LazyVStack(spacing: 10) {
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
                                    Text("Add a task above to plan your day")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(40)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    layoutPicker
                    CalendarHourlyGrid(viewModel: viewModel, date: Date())
                }
                .padding(.top, 4)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .sheet(item: $selectedTodo) { todo in
            TaskDetailView(todo: todo, viewModel: viewModel)
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

    private var quickAddBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.orange)

            TextField("Quick add a task...", text: $newTodoTitle)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .onSubmit(addQuickTodo)

            Button("Add", action: addQuickTodo)
                .font(.callout.weight(.bold))
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.15)))
        .padding(.horizontal)
    }

    private func addQuickTodo() {
        let title = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        viewModel.createTodo(
            title: title,
            doDate: Date(),
            dueDate: nil,
            plannedStartTime: nil,
            categoryId: viewModel.categories.first?.id
        )
        newTodoTitle = ""
    }
}

struct TaskListRowView: View {
    let todo: TodoEntry
    let category: Category?
    @ObservedObject var viewModel: TodoViewModel
    let onOpen: () -> Void

    private var categoryColor: Color {
        Color(hex: category?.colorHex ?? "7C6FF7")
    }

    private var isTimerActive: Bool {
        viewModel.activeTimerTodoId == todo.id
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.toggleComplete(todo)
            } label: {
                Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(todo.status == .completed ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(todo.title)
                            .font(.body.weight(.semibold))
                            .strikethrough(todo.status == .completed)
                            .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                            .lineLimit(2)

                        if let icon = category?.icon {
                            Text(icon)
                                .font(.caption)
                        }
                    }

                    if let plannedStartTime = todo.plannedStartTime, !plannedStartTime.isEmpty {
                        Text("\(plannedStartTime) · \(Int(todo.plannedDuration / 60)) min")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    Label(
                        isTimerActive ? "Stop" : "Start",
                        systemImage: isTimerActive ? "stop.fill" : "play.fill"
                    )
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Capsule().fill(isTimerActive ? Color.red : Color.indigo))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isTimerActive ? "Stop \(todo.title)" : "Start \(todo.title)")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.15)))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(categoryColor)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
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

    init(todo: TodoEntry, viewModel: TodoViewModel) {
        self.todo = todo
        self.viewModel = viewModel
        _title = State(initialValue: todo.title)
        _description = State(initialValue: todo.description ?? "")
        _doDate = State(initialValue: todo.doDate)
        _hasPlannedTime = State(initialValue: todo.plannedStartTime != nil)
        _plannedTime = State(initialValue: Self.date(from: todo.plannedStartTime) ?? Date())
        _durationMinutes = State(initialValue: max(15, Int(todo.plannedDuration / 60)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task title", text: $title)

                    TextEditor(text: $description)
                        .frame(minHeight: 140)
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
        updatedTodo.plannedStartTime = hasPlannedTime ? plannedTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) : nil
        updatedTodo.plannedDuration = TimeInterval(durationMinutes * 60)

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

#Preview("Today View") {
    TodayView(viewModel: TodoViewModel())
}
