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
        NavigationView {
            VStack(spacing: 12) {
                // Header Bar Row 1: Title, Date, Account Profile, Settings
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("📍 Today's Focus")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)

                        Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // User Account Profile Pill Button
                    Button {
                        viewModel.showingAccountModal = true
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.indigo)
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Text(viewModel.userAccount.name.prefix(1).uppercased())
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                )

                            Text("👑 \(viewModel.userAccount.tier)")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.indigo)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.indigo.opacity(0.15)))
                    }

                    // Settings Button
                    Button {
                        viewModel.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .bold))
                            .padding(8)
                            .background(Circle().fill(Color.indigo))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Header Bar Row 2: Full-Width Layout Switcher (List | Calendar | Kanban)
                Picker("Layout", selection: $viewModel.displayStyle) {
                    Text("List 📝").tag(DisplayStyle.list)
                    Text("Calendar 🗓️").tag(DisplayStyle.calendar)
                    Text("Kanban 📋").tag(DisplayStyle.kanban)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

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
                                            // Checkbox / Complete Button
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
                                                        .lineLimit(2)

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
                                                            .lineLimit(1)
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
                            .padding(.bottom, 20)
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
            .sheet(isPresented: $viewModel.showingAccountModal) {
                AccountView(viewModel: viewModel)
            }
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
    }
}
