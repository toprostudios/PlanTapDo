// FutureView.swift
import SwiftUI

struct FutureView: View {
    @ObservedObject var viewModel: TodoViewModel

    private var futureTodos: [TodoEntry] {
        let calendar = Calendar.current
        return viewModel.todos.filter { calendar.isDate($0.doDate, inSameDayAs: viewModel.selectedFutureDate) }
            .sorted { ($0.plannedStartTime ?? "23:59") < ($1.plannedStartTime ?? "23:59") }
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let offsetDate = calendar.date(byAdding: .weekOfYear, value: viewModel.currentWeekOffset, to: today) ?? today
        let weekday = calendar.component(.weekday, from: offsetDate)
        let daysToMonday = (weekday == 1) ? -6 : (2 - weekday)
        guard let monday = calendar.date(byAdding: .day, value: daysToMonday, to: offsetDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
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
                        Text("🗓️ Future Schedule")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        Text(viewModel.selectedFutureDate.formatted(.dateTime.weekday(.wide).month().day()))
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

                // Week Navigator Bar
                HStack {
                    Button {
                        viewModel.currentWeekOffset -= 1
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                            Text("Prev")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.indigo)
                    }

                    Spacer()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(weekDays, id: \.self) { day in
                                let isSelected = Calendar.current.isDate(day, inSameDayAs: viewModel.selectedFutureDate)
                                Button {
                                    viewModel.selectedFutureDate = day
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                            .font(.caption2.weight(.bold))
                                        Text(day.formatted(.dateTime.day()))
                                            .font(.subheadline.weight(.heavy))
                                    }
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isSelected ? Color.indigo : Color.secondary.opacity(0.12))
                                    )
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        viewModel.currentWeekOffset += 1
                    } label: {
                        HStack(spacing: 2) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.indigo)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)

                // Render selected layout: List, Calendar, or Kanban
                if viewModel.displayStyle == .list {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(futureTodos) { todo in
                                let cat = category(for: todo.categoryId)
                                let catColor = Color(hex: cat?.colorHex ?? "7C6FF7")

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(todo.title)
                                            .font(.body.weight(.bold))
                                        Spacer()
                                        if let icon = cat?.icon {
                                            Text(icon).font(.caption)
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
                    }
                } else if viewModel.displayStyle == .calendar {
                    CalendarHourlyGrid(viewModel: viewModel, date: viewModel.selectedFutureDate)
                } else {
                    KanbanBoardView(viewModel: viewModel, date: viewModel.selectedFutureDate)
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
