// KanbanBoardView.swift
import SwiftUI

struct KanbanBoardView: View {
    @ObservedObject var viewModel: TodoViewModel
    let date: Date

    private var dayTodos: [TodoEntry] {
        let calendar = Calendar.current
        return viewModel.todos.filter { calendar.isDate($0.doDate, inSameDayAs: date) }
    }

    private func todos(for status: TodoStatus) -> [TodoEntry] {
        dayTodos.filter { $0.status == status }
    }

    private func category(for catId: UUID?) -> Category? {
        guard let catId = catId else { return nil }
        return viewModel.categories.first { $0.id == catId }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                kanbanColumn(title: "To Do", icon: "📝", status: .pending, color: .indigo)
                kanbanColumn(title: "In Progress", icon: "⚡", status: .inProgress, color: .orange)
                kanbanColumn(title: "Completed", icon: "✅", status: .completed, color: .green)
            }
            .padding()
        }
        .background(Color.primary.opacity(0.02))
    }

    @ViewBuilder
    private func kanbanColumn(title: String, icon: String, status: TodoStatus, color: Color) -> some View {
        let items = todos(for: status)

        VStack(alignment: .leading, spacing: 12) {
            // Column Header
            HStack {
                Text("\(icon) \(title)")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(color)
                Spacer()
                Text("\(items.count)")
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.2)))
                    .foregroundStyle(color)
            }
            .padding(.bottom, 4)

            Divider()

            // Column Items Stack
            VStack(spacing: 10) {
                ForEach(items) { todo in
                    let cat = category(for: todo.categoryId)
                    let catColor = Color(hex: cat?.colorHex ?? "7C6FF7")

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(todo.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Spacer()
                            if let icon = cat?.icon {
                                Text(icon).font(.caption)
                            }
                        }

                        if let desc = todo.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        HStack(spacing: 6) {
                            Text("⏰ \(todo.plannedStartTime ?? "09:00")")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)

                            if let loc = todo.location, !loc.isEmpty {
                                Text("📍 \(loc)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.green)
                            }
                        }

                        // Quick Action Buttons
                        HStack(spacing: 8) {
                            if status != .inProgress {
                                Button("▶️ Start") {
                                    if let idx = viewModel.todos.firstIndex(where: { $0.id == todo.id }) {
                                        viewModel.todos[idx].status = .inProgress
                                    }
                                }
                                .font(.caption2.weight(.bold))
                                .buttonStyle(.bordered)
                                .tint(.orange)
                            }

                            if status != .completed {
                                Button("✅ Complete") {
                                    viewModel.toggleComplete(todo)
                                }
                                .font(.caption2.weight(.bold))
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
                    .overlay(
                        Rectangle().fill(catColor).frame(width: 4),
                        alignment: .leading
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if items.isEmpty {
                    VStack {
                        Text("No tasks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), style: StrokeStyle(dash: [5])))
                }
            }
        }
        .frame(width: 260)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
    }
}
