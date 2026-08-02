// TodayView.swift
import SwiftUI

struct TodayView: View {
    @ObservedObject var viewModel: TodoViewModel

    @State private var newTodoTitle: String = ""
    @State private var selectedCategory: Category? = nil

    private var todayTodos: [TodoEntry] {
        let calendar = Calendar.current
        return viewModel.todos.filter { calendar.isDateInToday($0.doDate) }
            .sorted { ($0.plannedStartTime ?? "23:59") < ($1.plannedStartTime ?? "23:59") }
    }

    private func category(for catId: UUID?) -> Category? {
        guard let catId = catId else { return nil }
        return viewModel.categories.first { $0.id == catId }
    }

    var body: some View {
        ScreenContainer(maxWidth: 600) {
            VStack(spacing: 12) {
                // Layout Switcher (List | Calendar | Kanban)
                Picker("Layout", selection: $viewModel.displayStyle) {
                    Text("List 📝").tag(DisplayStyle.list)
                    Text("Calendar 🗓️").tag(DisplayStyle.calendar)
                    Text("Kanban 📋").tag(DisplayStyle.kanban)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 4)

                // Render selected layout: List, Calendar, or Kanban
                if viewModel.displayStyle == .list {
                    VStack(spacing: 12) {
                        // Quick Add Input Bar
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.orange)
                            TextField("Quick add task for Today...", text: $newTodoTitle)
                                .textFieldStyle(.plain)
                                .font(.subheadline)

                            Button {
                                guard !newTodoTitle.isEmpty else { return }
                                viewModel.createTodo(
                                    title: newTodoTitle,
                                    description: nil,
                                    doDate: Date(),
                                    dueDate: Date(),
                                    categoryId: selectedCategory?.id ?? viewModel.categories.first?.id
                                )
                                newTodoTitle = ""
                            } label: {
                                Text("Add")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.indigo))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray).opacity(0.15))
                        .padding(.horizontal)

                        // Task List
                        LazyVStack(spacing: 10) {
                            ForEach(todayTodos) { todo in
                                TodayTodoRowView(
                                    todo: todo,
                                    category: category(for: todo.categoryId),
                                    viewModel: viewModel
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
                } else if viewModel.displayStyle == .calendar {
                    CalendarHourlyGrid(viewModel: viewModel, date: Date())
                } else {
                    KanbanBoardView(viewModel: viewModel, date: Date())
                }
            }
        }
    }
}

// Extracted Row Subview for Type-Checker Performance
struct TodayTodoRowView: View {
    let todo: TodoEntry
    let category: Category?
    let viewModel: TodoViewModel

    private var catColor: Color {
        Color(hex: category?.colorHex ?? "7C6FF7")
    }

    private var isTimerActive: Bool {
        viewModel.activeTimerTodoId == todo.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    viewModel.toggleComplete(todo)
                } label: {
                    Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(todo.status == .completed ? .green : .secondary)
                }

                Text(todo.title)
                    .font(.body.weight(.bold))
                    .strikethrough(todo.status == .completed)
                    .foregroundStyle(todo.status == .completed ? .secondary : .primary)
                    .lineLimit(2)

                Spacer()

                if let icon = category?.icon {
                    Text(icon).font(.caption)
                }
            }

            HStack(spacing: 8) {
                Text("⏰ \(todo.plannedStartTime ?? "09:00") (\(Int(todo.plannedDuration / 60))m)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let loc = todo.location, !loc.isEmpty {
                    Text("📍 \(loc)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
            }

            if let desc = todo.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Timer controls row
            HStack {
                Spacer()
                if isTimerActive {
                    Button {
                        viewModel.stopTimer()
                    } label: {
                        Label("Stop (\(viewModel.timerFormatted))", systemImage: "stop.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        viewModel.startTimer(for: todo)
                    } label: {
                        Label("Start Timer", systemImage: "play.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.indigo)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray).opacity(0.15))
        .overlay(
            Rectangle().fill(catColor).frame(width: 4),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}

#Preview("Today View") {
    TodayView(viewModel: TodoViewModel())
}
