// TeamView.swift
import SwiftUI

struct TeamView: View {
    @ObservedObject var viewModel: TodoViewModel

    private func category(for catId: UUID?) -> Category? {
        guard let catId = catId else { return nil }
        return viewModel.categories.first { $0.id == catId }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 4) {
                        Text("👥 Team & Manager Workspace")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("View multiple team members at once, in-progress tasks & lined up schedules")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)

                    // Multi-Person Team Member List
                    ForEach(viewModel.teamMembers) { member in
                        let memberTodos = viewModel.todos.filter { $0.assigneeId == member.id || $0.assigneeId == nil }
                        let currentTask = memberTodos.first { $0.status == .inProgress }
                        let linedUpTasks = memberTodos.filter { $0.status == .pending }
                        let totalPlannedMin = memberTodos.reduce(0) { $0 + Int($1.plannedDuration / 60) }

                        VStack(alignment: .leading, spacing: 12) {
                            // Member Profile Header
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.indigo)
                                    .frame(width: 42, height: 42)
                                    .overlay(
                                        Text(member.name.prefix(1).uppercased())
                                            .font(.headline.weight(.bold))
                                            .foregroundStyle(.white)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.headline.weight(.bold))
                                    Text(member.role)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(member.department)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            }

                            // Workload Capacity
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Workload").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(totalPlannedMin)m / \(member.capacityMinutes)m")
                                        .font(.caption2.weight(.bold))
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.secondary.opacity(0.15))
                                        Capsule().fill(Color.indigo)
                                            .frame(width: max(4, geo.size.width * CGFloat(min(1.0, Double(totalPlannedMin) / Double(member.capacityMinutes)))))
                                    }
                                }
                                .frame(height: 6)
                            }

                            // Current Task Box
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("🔴 ACTIVE NOW")
                                        .font(.system(size: 8, weight: .black))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.red.opacity(0.2)))
                                        .foregroundStyle(.red)
                                    Text("Current Task")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.secondary)
                                }

                                if let task = currentTask {
                                    let cat = category(for: task.categoryId)
                                    let catColor = Color(hex: cat?.colorHex ?? "7C6FF7")

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title).font(.subheadline.weight(.bold))
                                        Text("⏰ Started: \(task.plannedStartTime ?? "09:00") (\(Int(task.plannedDuration / 60))m)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                                    .overlay(Rectangle().fill(catColor).frame(width: 4), alignment: .leading)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    Text("No active task running")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(8)
                                }
                            }

                            // Lined Up Tasks
                            VStack(alignment: .leading, spacing: 6) {
                                Text("📋 LINED UP TASKS (\(linedUpTasks.count))")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(.secondary)

                                ForEach(linedUpTasks.prefix(3)) { task in
                                    HStack {
                                        Text(task.title)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("⏰ \(task.plannedStartTime ?? "09:00")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
                                }
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
        }
    }
}
