// FutureView.swift
import SwiftUI

struct FutureView: View {
    @ObservedObject var viewModel: TodoViewModel
    @State private var selectedTodo: TodoEntry?

    private var futureTodos: [TodoEntry] {
        viewModel.todos
            .filter { Calendar.current.isDate($0.doDate, inSameDayAs: viewModel.selectedFutureDate) }
            .sorted { ($0.plannedStartTime ?? "23:59") < ($1.plannedStartTime ?? "23:59") }
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

    var body: some View {
        Group {
            if viewModel.displayStyle == .list {
                ScreenContainer(maxWidth: 600) {
                    VStack(spacing: 10) {
                        layoutPicker
                        weekNavigator
                        listContent
                    }
                }
            } else {
                VStack(spacing: 8) {
                    layoutPicker
                    weekNavigator
                    CalendarHourlyGrid(viewModel: viewModel, date: viewModel.selectedFutureDate)
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

    private var weekNavigator: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.currentWeekOffset -= 1
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
                    Button {
                        viewModel.selectedFutureDate = day
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.caption2.weight(.bold))
                            Text(day.formatted(.dateTime.day()))
                                .font(.subheadline.weight(.heavy))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected ? Color.indigo : Color.secondary.opacity(0.12))
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                viewModel.currentWeekOffset += 1
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 44)
                    .foregroundStyle(.indigo)
            }
            .accessibilityLabel("Next week")
        }
        .padding(.horizontal)
    }

    private var listContent: some View {
        LazyVStack(spacing: 10) {
            ForEach(futureTodos) { todo in
                TaskListRowView(
                    todo: todo,
                    category: category(for: todo.categoryId),
                    viewModel: viewModel,
                    onOpen: { selectedTodo = todo }
                )
            }

            if futureTodos.isEmpty {
                VStack(spacing: 8) {
                    Text("🎉 No tasks scheduled")
                        .font(.headline)
                    Text("Select another day above or create a new task")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(40)
            }
        }
        .padding(.bottom, 20)
    }
}

#Preview("Future View") {
    FutureView(viewModel: TodoViewModel())
}
