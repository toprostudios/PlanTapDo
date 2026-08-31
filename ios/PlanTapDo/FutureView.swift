// FutureView.swift
import SwiftUI

struct FutureView: View {
    @ObservedObject var viewModel: TodoViewModel
    @State private var selectedTodo: TodoEntry?
    @State private var showingTaskComposer = false

    private var activeFutureTodos: [TodoEntry] {
        todos(on: viewModel.selectedFutureDate, with: { $0.status != .completed })
    }

    private var completedFutureTodos: [TodoEntry] {
        guard viewModel.showCompletedTasks else { return [] }
        return todos(on: viewModel.selectedFutureDate, with: { $0.status == .completed })
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
            let leftTime = $0.plannedStartTime ?? "23:59"
            let rightTime = $1.plannedStartTime ?? "23:59"
            return leftTime == rightTime
                ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                : leftTime < rightTime
        }
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let offsetDate = calendar.date(byAdding: .weekOfYear, value: viewModel.currentWeekOffset, to: today) ?? today
        let weekday = calendar.component(.weekday, from: offsetDate)
        let daysToMonday = weekday == 1 ? -6 : 2 - weekday
        guard let monday = calendar.date(byAdding: .day, value: daysToMonday, to: offsetDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func category(for categoryId: UUID?) -> Category? {
        guard let categoryId else { return nil }
        return viewModel.categories.first { $0.id == categoryId }
    }

    /// A week can cross a month boundary, so show every month represented in
    /// the strip rather than making the selected day the only point of context.
    private var weekMonthTitle: String {
        var titles: [String] = []
        for day in weekDays {
            let title = day.formatted(.dateTime.month(.wide).year())
            if !titles.contains(title) {
                titles.append(title)
            }
        }
        return titles.joined(separator: " – ")
    }

    var body: some View {
        Group {
            if viewModel.displayStyle == .list {
                ScreenContainer(maxWidth: 600) {
                    VStack(spacing: 10) {
                        pageHeader
                        layoutPicker
                        weekNavigator
                        listContent
                    }
                }
            } else {
                VStack(spacing: 8) {
                    pageHeader
                    layoutPicker
                    weekNavigator
                    CalendarHourlyGrid(
                        viewModel: viewModel,
                        date: viewModel.selectedFutureDate,
                        onOpenTask: { selectedTodo = $0 },
                        showsTodayBadge: true
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
            TaskComposerView(viewModel: viewModel, start: viewModel.selectedFutureDate)
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
                .accessibilityLabel("Add task")
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
        Text("Upcoming")
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }

    private var weekNavigator: some View {
        VStack(spacing: 6) {
            Text(weekMonthTitle)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 6) {
                Button {
                    AppHaptics.selection()
                    viewModel.currentWeekOffset -= 1
                    if let newDate = Calendar.current.date(byAdding: .day, value: -7, to: viewModel.selectedFutureDate) {
                        viewModel.selectedFutureDate = newDate
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 44)
                        .foregroundStyle(.indigo)
                }
                .accessibilityLabel("Previous week")

                HStack(spacing: 4) {
                    ForEach(weekDays, id: \.self) { day in
                        let isSelected = Calendar.current.isDate(day, inSameDayAs: viewModel.selectedFutureDate)
                        let isToday = Calendar.current.isDateInToday(day)
                        Button {
                            AppHaptics.selection()
                            viewModel.selectedFutureDate = day
                        } label: {
                            VStack(spacing: 2) {
                                Text(isToday ? "T" : day.formatted(.dateTime.weekday(.narrow)))
                                    .font(.caption2.weight(.bold))
                                Text(day.formatted(.dateTime.day()))
                                    .font(.subheadline.weight(.heavy))
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(
                                        isSelected ? Color.indigo
                                            : (isToday ? Color.green : Color.secondary.opacity(0.12))
                                    )
                            )
                            .foregroundStyle(isSelected || isToday ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            isToday
                                ? "Today, \(day.formatted(date: .complete, time: .omitted))"
                                : day.formatted(date: .complete, time: .omitted)
                        )
                    }
                }
                .frame(maxWidth: .infinity)

                Button {
                    AppHaptics.selection()
                    viewModel.currentWeekOffset += 1
                    if let newDate = Calendar.current.date(byAdding: .day, value: 7, to: viewModel.selectedFutureDate) {
                        viewModel.selectedFutureDate = newDate
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 44)
                        .foregroundStyle(.indigo)
                }
                .accessibilityLabel("Next week")
            }
        }
        .padding(.horizontal)
    }

    private var listContent: some View {
        LazyVStack(spacing: 6) {
            ForEach(activeFutureTodos) { todo in
                TaskListRowView(
                    todo: todo,
                    category: category(for: todo.categoryId),
                    viewModel: viewModel,
                    onOpen: { selectedTodo = todo }
                )
            }

            if activeFutureTodos.isEmpty {
                VStack(spacing: 8) {
                    Text("🎉 No tasks scheduled")
                        .font(.headline)
                }
                .padding(40)
            }

            CompletedTaskListSection(
                todos: completedFutureTodos,
                viewModel: viewModel,
                categoryFor: category,
                onOpen: { selectedTodo = $0 }
            )
        }
        .padding(.bottom, 20)
    }
}

struct FutureView_Previews: PreviewProvider {
    static var previews: some View { FutureView(viewModel: TodoViewModel()) }
}
