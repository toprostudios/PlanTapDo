// TodayView.swift
import SwiftUI
import UniformTypeIdentifiers

struct TodayView: View {
    @ObservedObject var viewModel: TodoViewModel

    @State private var selectedTodo: TodoEntry?
    @State private var showingTaskComposer = false
    @State private var draggingTodoID: UUID?
    @State private var dropTargetTodoID: UUID?

    private var activeTodayTodos: [TodoEntry] {
        todos(on: Date(), with: { $0.status != .completed })
    }

    private var completedTodayTodos: [TodoEntry] {
        guard viewModel.showCompletedTasks else { return [] }
        return todos(on: Date(), with: { $0.status == .completed })
    }

    private func todos(on date: Date, with statusMatches: (TodoEntry) -> Bool) -> [TodoEntry] {
        viewModel.todos.filter {
            Calendar.current.isDate($0.doDate, inSameDayAs: date)
                && statusMatches($0)
                && $0.status != .archived
                && $0.status != .skipped
                && viewModel.shouldDisplayInList($0)
        }
        .sorted {
            if $0.sortOrder != $1.sortOrder, $0.sortOrder != 0 || $1.sortOrder != 0 {
                let leftOrder = $0.sortOrder == 0 ? Int.max : $0.sortOrder
                let rightOrder = $1.sortOrder == 0 ? Int.max : $1.sortOrder
                return leftOrder < rightOrder
            }
            let leftTime = $0.plannedStartTime ?? "23:59"
            let rightTime = $1.plannedStartTime ?? "23:59"
            return leftTime == rightTime
                ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                : leftTime < rightTime
        }
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
                            ForEach(activeTodayTodos) { todo in
                                TaskListRowView(
                                    todo: todo,
                                    category: category(for: todo.categoryId),
                                    viewModel: viewModel,
                                    onOpen: { selectedTodo = todo }
                                )
                                .overlay(alignment: .top) {
                                    if dropTargetTodoID == todo.id, draggingTodoID != todo.id {
                                        Capsule()
                                            .fill(Color.indigo)
                                            .frame(height: 3)
                                            .padding(.horizontal, 8)
                                            .transition(.opacity.combined(with: .scale))
                                    }
                                }
                                .animation(.spring(response: 0.18, dampingFraction: 0.82), value: dropTargetTodoID)
                                .onDrag {
                                    draggingTodoID = todo.id
                                    return NSItemProvider(object: todo.id.uuidString as NSString)
                                }
                                .onDrop(of: [UTType.plainText], delegate: TodayTaskDropDelegate(
                                    destinationID: todo.id,
                                    draggingTodoID: $draggingTodoID,
                                    dropTargetTodoID: $dropTargetTodoID,
                                    visibleIDs: activeTodayTodos.map(\.id),
                                    onReorder: viewModel.setManualListOrder
                                ))
                            }

                            if activeTodayTodos.isEmpty {
                                VStack(spacing: 8) {
                                    Text("🎉 All clear for Today!")
                                        .font(.headline)
                                }
                                .padding(40)
                            }

                            CompletedTaskListSection(
                                todos: completedTodayTodos,
                                viewModel: viewModel,
                                categoryFor: category,
                                onOpen: { selectedTodo = $0 }
                            )
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

/// Keeps finished tasks out of the active stream while preserving the optional
/// completed-task setting in every normal task list.
struct CompletedTaskListSection: View {
    let todos: [TodoEntry]
    @ObservedObject var viewModel: TodoViewModel
    let categoryFor: (UUID?) -> Category?
    let onOpen: (TodoEntry) -> Void
    var usesOuterPadding = true
    @State private var isExpanded = false

    var body: some View {
        if !todos.isEmpty {
            Divider().padding(.vertical, 6)

            Button {
                AppHaptics.selection()
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Completed (\(todos.count))")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, usesOuterPadding ? 16 : 0)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(todos) { todo in
                    TaskListRowView(
                        todo: todo,
                        category: categoryFor(todo.categoryId),
                        viewModel: viewModel,
                        onOpen: { onOpen(todo) },
                        usesOuterPadding: usesOuterPadding
                    )
                }
            }
        }
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
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let icon = category?.icon {
                            Text(icon)
                                .font(.caption)
                        }
                    }

                    if let plannedStartTime = todo.plannedStartTime, !plannedStartTime.isEmpty {
                        Label("\(plannedStartTime) · \(durationLabel)", systemImage: "clock")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    } else if todo.plannedDuration == 0 {
                        Label("5 min estimate · not on calendar", systemImage: "clock")
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
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: todo.status == .completed
                            ? [Color.secondary.opacity(0.10), Color.secondary.opacity(0.05)]
                            : [taskColor.opacity(0.16), Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92)],
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
            Rectangle()
                .fill(taskColor)
                .frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: taskColor.opacity(0.10), radius: 12, y: 5)
        .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
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

    private var durationLabel: String {
        todo.plannedDuration == 0
            ? "5 min estimate · not on calendar"
            : "\(Int(todo.plannedDuration / 60)) min"
    }
}

private struct TodayTaskDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var draggingTodoID: UUID?
    @Binding var dropTargetTodoID: UUID?
    let visibleIDs: [UUID]
    let onReorder: ([UUID]) -> Void

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggingTodoID,
              sourceID != destinationID else { return }

        withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
            dropTargetTodoID = destinationID
        }
    }

    func dropExited(info: DropInfo) {
        guard dropTargetTodoID == destinationID else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.82)) {
            dropTargetTodoID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggingTodoID = nil
            dropTargetTodoID = nil
        }

        guard let sourceID = draggingTodoID,
              sourceID != destinationID,
              let sourceIndex = visibleIDs.firstIndex(of: sourceID),
              let destinationIndex = visibleIDs.firstIndex(of: destinationID) else { return false }

        var reordered = visibleIDs
        reordered.remove(at: sourceIndex)
        reordered.insert(sourceID, at: min(destinationIndex, reordered.count))
        onReorder(reordered)
        return true
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
        let todo = viewModel.editableTodo(for: todo)
        self.todo = todo
        self.viewModel = viewModel
        _title = State(initialValue: todo.title)
        _description = State(initialValue: todo.description ?? "")
        _doDate = State(initialValue: todo.doDate)
        _hasPlannedTime = State(initialValue: todo.plannedStartTime != nil)
        _plannedTime = State(initialValue: Self.date(from: todo.plannedStartTime) ?? Date())
        _durationMinutes = State(initialValue: max(0, Int(todo.plannedDuration / 60)))
        _categoryId = State(initialValue: todo.categoryId)
        _recurrenceFrequency = State(initialValue: todo.recurrenceFrequency)
        _recurrenceWeekdays = State(initialValue: Set(todo.recurrenceWeekdays ?? []))
        _notificationPreference = State(initialValue: todo.notificationPreference)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Task title", text: $title, axis: .vertical)
                        .lineLimit(1...2)
                        .modernTextInput()

                    TextField("Add a description or notes", text: $description, axis: .vertical)
                        .lineLimit(1...5)
                        .modernTextInput()
                }

                Section("Schedule") {
                    RelativeDayWheelPicker(date: $doDate, dayRange: -30...365)
                    Toggle("Set a time", isOn: $hasPlannedTime)

                    if hasPlannedTime {
                        FiveMinuteTimePicker(date: $plannedTime)
                    }

                    Picker("Duration", selection: $durationMinutes) {
                        ForEach(detailDurationChoices, id: \.self) { minutes in
                            Text(detailDurationLabel(minutes)).tag(minutes)
                        }
                    }
                    if durationMinutes == 0 {
                        Text("Unspecified tasks stay in the list and do not appear on the calendar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                    Section {
                        NotificationPreferencePicker(
                            preference: $notificationPreference,
                            inheritedPreference: categoryId.flatMap { id in viewModel.categories.first { $0.id == id }?.notificationPreference },
                            allowsInheritedDefault: true
                        )
                    }
                }

                Section {
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

    private var detailDurationChoices: [Int] {
        Array(Set([0, 5, 15, 30, 45, 60, 90, 120, durationMinutes])).sorted()
    }

    private func detailDurationLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "Unspecified (5 min estimate)" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours) hr \(remainder) min"
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
