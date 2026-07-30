// TodayView.swift
import SwiftUI

struct TodayView: View {
    @ObservedObject var viewModel: TodoViewModel

    @State private var newTodoTitle: String = ""
    @State private var selectedCategory: Category? = nil
    @State private var newSubtaskTitle: String = ""

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
        NavigationView {
            VStack(spacing: 0) {
                // Header Bar with Prominent Settings Button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("📍 Today's Focus")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Toggle View Switcher: List | Calendar | Kanban
                    Picker("Layout", selection: $viewModel.displayStyle) {
                        Text("List").tag(DisplayStyle.list)
                        Text("Calendar").tag(DisplayStyle.calendar)
                        Text("Kanban").tag(DisplayStyle.kanban)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)

                    // Prominent Settings Button
                    Button {
                        viewModel.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .bold))
                            .padding(8)
                            .background(Circle().fill(Color.indigo))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Render selected layout: List, Calendar, or Kanban
                if viewModel.displayStyle == .list {
                    VStack(spacing: 12) {
                        // Quick Add Input
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.orange)
                            TextField("Quick add task for Today...", text: $newTodoTitle)
                                .textFieldStyle(.plain)
                                .font(.body)

                            Button {
                                guard !newTodoTitle.isEmpty else { return }
                                viewModel.createTodo(
                                    title: newTodoTitle,
                                    description: nil,
                                    doDate: Date(),
                                    dueDate: Date(),
                                    dueTime: "18:00",
                                    descriptiveDeadline: nil,
                                    plannedStartTime: "09:00",
                                    plannedDuration: 1800,
                                    categoryId: selectedCategory?.id ?? viewModel.categories.first?.id,
                                    priority: .medium,
                                    location: nil,
                                    reminder: nil,
                                    labels: nil
                                )
                                newTodoTitle = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.indigo)
                            }
                            .disabled(newTodoTitle.isEmpty)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.06)))
                        .padding(.horizontal)

                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(todayTodos) { todo in
                                    let cat = category(for: todo.categoryId)
                                    let catColor = Color(hex: cat?.colorHex ?? "7C6FF7")

                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(spacing: 10) {
                                            // Start / Stop Timer Button
                                            Button {
                                                viewModel.toggleComplete(todo)
                                            } label: {
                                                Image(systemName: todo.status == .completed ? "checkmark.circle.fill" : "circle")
                                                    .font(.title3)
                                                    .foregroundStyle(todo.status == .completed ? .green : .indigo)
                                            }

                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack {
                                                    Text(todo.title)
                                                        .font(.body.weight(.bold))
                                                        .strikethrough(todo.status == .completed)

                                                    Spacer()

                                                    if let icon = cat?.icon {
                                                        Text(icon)
                                                            .font(.caption)
                                                            .padding(4)
                                                            .background(Circle().fill(catColor.opacity(0.2)))
                                                    }
                                                }

                                                HStack(spacing: 6) {
                                                    Text("⏰ \(todo.plannedStartTime ?? "09:00") (\(Int(todo.plannedDuration / 60))m)")
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(.secondary)

                                                    if let loc = todo.location, !loc.isEmpty {
                                                        Text("📍 \(loc)")
                                                            .font(.caption.weight(.bold))
                                                            .foregroundStyle(.green)
                                                    }

                                                    if let priority = todo.priority {
                                                        Text(priority.badgeText)
                                                            .font(.caption2.weight(.black))
                                                            .foregroundStyle(.red)
                                                    }
                                                }

                                                if let deadline = todo.descriptiveDeadline {
                                                    Text("📝 \(deadline)")
                                                        .font(.caption2.weight(.semibold))
                                                        .foregroundStyle(.purple)
                                                }
                                            }
                                        }

                                        // Subtasks Checklist Section
                                        if let subtasks = todo.subtasks, !subtasks.isEmpty {
                                            VStack(alignment: .leading, spacing: 6) {
                                                ForEach(subtasks) { st in
                                                    HStack(spacing: 8) {
                                                        Button {
                                                            viewModel.toggleSubtask(todoId: todo.id, subtaskId: st.id)
                                                        } label: {
                                                            Image(systemName: st.isCompleted ? "checkmark.square.fill" : "square")
                                                                .font(.caption)
                                                                .foregroundStyle(st.isCompleted ? .green : .secondary)
                                                        }

                                                        Text(st.title)
                                                            .font(.caption)
                                                            .strikethrough(st.isCompleted)
                                                            .foregroundStyle(st.isCompleted ? .secondary : .primary)
                                                    }
                                                }
                                            }
                                            .padding(.leading, 32)
                                        }
                                    }
                                    .padding(14)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
                                    .overlay(
                                        Rectangle().fill(catColor).frame(width: 4),
                                        alignment: .leading
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                } else if viewModel.displayStyle == .calendar {
                    CalendarHourlyGrid(viewModel: viewModel, date: Date())
                } else {
                    KanbanBoardView(viewModel: viewModel, date: Date())
                }
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .sheet(isPresented: $viewModel.showingSettings) {
                SettingsView(viewModel: viewModel)
            }
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }
}
