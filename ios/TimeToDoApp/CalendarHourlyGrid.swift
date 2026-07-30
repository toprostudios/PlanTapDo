// CalendarHourlyGrid.swift
import SwiftUI

struct CalendarHourlyGrid: View {
    @ObservedObject var viewModel: TodoViewModel
    let date: Date

    // Calendar view span: 1 Day, 3 Days, 7 Days (Week)
    @State private var calendarSpan: Int = 1

    private let hours = Array(7...22) // 7 AM to 10 PM
    @State private var now = Date()
    @State private var draggingTodoId: UUID? = nil
    @State private var dragYTranslation: CGFloat = 0

    // Compute visible dates based on calendarSpan (1, 3, 7)
    private var visibleDates: [Date] {
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: date)

        if calendarSpan == 1 {
            return [baseDate]
        } else if calendarSpan == 3 {
            return (0..<3).compactMap { calendar.date(byAdding: .day, value: $0, to: baseDate) }
        } else {
            // Weekly View (7 Days starting Monday)
            let weekday = calendar.component(.weekday, from: baseDate)
            let daysToMonday = (weekday == 1) ? -6 : (2 - weekday)
            guard let monday = calendar.date(byAdding: .day, value: daysToMonday, to: baseDate) else { return [] }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        }
    }

    private func category(for catId: UUID?) -> Category? {
        guard let catId = catId else { return nil }
        return viewModel.categories.first { $0.id == catId }
    }

    private var currentTimePx: CGFloat {
        let h = CGFloat(Calendar.current.component(.hour, from: now))
        let m = CGFloat(Calendar.current.component(.minute, from: now))
        return (h - 7.0) * 60.0 + (m / 60.0) * 60.0
    }

    private func dayTodos(for targetDate: Date) -> [TodoEntry] {
        let calendar = Calendar.current
        return viewModel.todos.filter { calendar.isDate($0.doDate, inSameDayAs: targetDate) }
            .sorted { ($0.plannedStartTime ?? "23:59") < ($1.plannedStartTime ?? "23:59") }
    }

    private func computeTransportBlocks(for targetDate: Date) -> [(id: String, from: String, to: String, top: CGFloat, height: CGFloat, duration: Int)] {
        let sorted = dayTodos(for: targetDate)
        var result: [(id: String, from: String, to: String, top: CGFloat, height: CGFloat, duration: Int)] = []

        guard sorted.count > 1 else { return result }

        for i in 0..<(sorted.count - 1) {
            let taskA = sorted[i]
            let taskB = sorted[i + 1]

            guard let locA = taskA.location?.trimmingCharacters(in: .whitespaces),
                  let locB = taskB.location?.trimmingCharacters(in: .whitespaces),
                  !locA.isEmpty, !locB.isEmpty,
                  locA.lowercased() != locB.lowercased() else { continue }

            let partsA = (taskA.plannedStartTime ?? "09:00").split(separator: ":").compactMap { Double($0) }
            let hA = partsA.first ?? 9.0
            let mA = partsA.count > 1 ? partsA[1] : 0.0
            let endMinA = hA * 60.0 + mA + (taskA.plannedDuration / 60.0)

            let partsB = (taskB.plannedStartTime ?? "10:00").split(separator: ":").compactMap { Double($0) }
            let hB = partsB.first ?? 10.0
            let mB = partsB.count > 1 ? partsB[1] : 0.0
            let startMinB = hB * 60.0 + mB

            if startMinB >= endMinA {
                let duration = viewModel.getTravelTimeBetweenLocations(locA, locB)
                let topPx = ((endMinA / 60.0) - 7.0) * 60.0
                let heightPx = max(20.0, (CGFloat(duration) / 60.0) * 60.0)

                result.append((
                    id: "\(taskA.id)-\(taskB.id)",
                    from: locA,
                    to: locB,
                    top: topPx,
                    height: heightPx,
                    duration: duration
                ))
            }
        }

        return result
    }

    private func computeOverlapLayouts(for targetDate: Date) -> [UUID: (colIndex: Int, totalCols: Int)] {
        let sorted = dayTodos(for: targetDate).map { t -> (todo: TodoEntry, startMin: Double, endMin: Double) in
            let parts = (t.plannedStartTime ?? "09:00").split(separator: ":").compactMap { Double($0) }
            let h = parts.first ?? 9.0
            let m = parts.count > 1 ? parts[1] : 0.0
            let startMin = h * 60.0 + m
            let endMin = startMin + (t.plannedDuration / 60.0)
            return (t, startMin, endMin)
        }

        var map: [UUID: (colIndex: Int, totalCols: Int)] = [:]

        for item in sorted {
            let overlaps = sorted.filter { other in
                other.todo.id != item.todo.id && item.startMin < other.endMin && item.endMin > other.startMin
            }

            if overlaps.isEmpty {
                map[item.todo.id] = (0, 1)
            } else {
                let cluster = ([item] + overlaps).sorted { $0.todo.id.uuidString < $1.todo.id.uuidString }
                let colIdx = cluster.firstIndex(where: { $0.todo.id == item.todo.id }) ?? 0
                map[item.todo.id] = (colIdx, cluster.count)
            }
        }

        return map
    }

    var body: some View {
        GeometryReader { outerGeo in
            let totalAvailableWidth = max(300, outerGeo.size.width)
            let timeColWidth: CGFloat = 50
            let gridWidth = totalAvailableWidth - timeColWidth

            let calculatedColWidth: CGFloat = {
                if calendarSpan == 1 {
                    return gridWidth - 10
                } else if calendarSpan == 3 {
                    return max(110, gridWidth / 3.0)
                } else {
                    return 110
                }
            }()

            VStack(spacing: 0) {
                // Header Bar with 1 Day | 3 Days | Week Segmented Control
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendar Grid")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("\(visibleDates.count) Day View")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Mode Selector Segmented Picker
                    Picker("Span", selection: $calendarSpan) {
                        Text("1 Day").tag(1)
                        Text("3 Days").tag(3)
                        Text("Week").tag(7)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))

                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        // Hour Grid Lines & Labels Column
                        VStack(spacing: 0) {
                            Text("Time")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(height: 32)

                            ForEach(hours, id: \.self) { hour in
                                HStack(alignment: .top) {
                                    Text(formatHour(hour))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .trailing)
                                }
                                .frame(height: 60)
                            }
                        }
                        .frame(width: timeColWidth)

                        // Multi-Day Columns
                        HStack(spacing: 0) {
                            ForEach(visibleDates, id: \.self) { colDate in
                                let todosForDay = dayTodos(for: colDate)
                                let overlapMap = computeOverlapLayouts(for: colDate)
                                let transportBlocks = computeTransportBlocks(for: colDate)
                                let isColToday = Calendar.current.isDateInToday(colDate)
                                let formattedDateStr = colDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())

                                VStack(spacing: 0) {
                                    // Column Day Header
                                    HStack(spacing: 4) {
                                        Text(formattedDateStr)
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(isColToday ? Color.indigo : Color.primary)
                                            .lineLimit(1)
                                        if isColToday {
                                            Text("TODAY")
                                                .font(.system(size: 7, weight: .black))
                                                .padding(.horizontal, 3)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(Color.indigo))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(height: 32)
                                    .frame(maxWidth: .infinity)
                                    .background(isColToday ? Color.indigo.opacity(0.1) : Color.secondary.opacity(0.06))
                                    .border(Color.secondary.opacity(0.15), width: 0.5)

                                    // Hour Grid Lines & Task Cards Container
                                    GeometryReader { geo in
                                        ZStack(alignment: .topLeading) {
                                            // Grid lines
                                            VStack(spacing: 0) {
                                                ForEach(hours, id: \.self) { _ in
                                                    VStack {
                                                        Divider()
                                                        Spacer()
                                                    }
                                                    .frame(height: 60)
                                                }
                                            }

                                            // Current Time Bar
                                            if isColToday {
                                                let h = Calendar.current.component(.hour, from: now)
                                                if h >= 7 && h <= 22 {
                                                    Rectangle()
                                                        .fill(Color.red)
                                                        .frame(height: 2)
                                                        .offset(y: currentTimePx)
                                                }
                                            }

                                            // Render Transport Time Blocks
                                            ForEach(transportBlocks, id: \.id) { tb in
                                                HStack(spacing: 2) {
                                                    Text("🚗")
                                                        .font(.system(size: 9))
                                                    Text("\(tb.duration)m: \(tb.from) ➔ \(tb.to)")
                                                        .font(.system(size: 8, weight: .bold))
                                                        .foregroundStyle(.orange)
                                                        .lineLimit(1)
                                                }
                                                .padding(.horizontal, 4)
                                                .frame(width: max(40, geo.size.width - 6), height: tb.height, alignment: .leading)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(Color.orange.opacity(0.18))
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [3]))
                                                )
                                                .offset(x: 3, y: tb.top)
                                            }

                                            // Render Task Cards
                                            ForEach(todosForDay) { todo in
                                                let metrics = getPushedMetrics(for: todo, targetDate: colDate)
                                                let cat = category(for: todo.categoryId)
                                                let layout = overlapMap[todo.id] ?? (0, 1)

                                                CalendarCardView(
                                                    todo: todo,
                                                    metrics: metrics,
                                                    cat: cat,
                                                    layout: layout,
                                                    containerWidth: geo.size.width,
                                                    draggingTodoId: draggingTodoId,
                                                    dragYTranslation: dragYTranslation,
                                                    viewModel: viewModel,
                                                    onDragChanged: { offset in
                                                        draggingTodoId = todo.id
                                                        dragYTranslation = offset
                                                    },
                                                    onDragEnded: { offset in
                                                        draggingTodoId = nil
                                                        dragYTranslation = 0
                                                        updateTimeForTodo(todo, verticalOffset: offset)
                                                    }
                                                )
                                            }
                                        }
                                    }
                                    .frame(height: CGFloat(hours.count * 60))
                                }
                                .frame(width: calculatedColWidth)
                                .border(Color.secondary.opacity(0.15), width: 0.5)
                            }
                        }
                    }
                }
            }
            .background(Color.primary.opacity(0.02))
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { input in
            now = input
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h):00 \(period)"
    }

    private func getPushedMetrics(for todo: TodoEntry, targetDate: Date) -> (top: CGFloat, height: CGFloat, isPushed: Bool, compressedMinutes: Int) {
        let timeStr = todo.plannedStartTime ?? "09:00"
        let parts = timeStr.split(separator: ":").compactMap { Double($0) }
        let h = parts.first ?? 9.0
        let m = parts.count > 1 ? parts[1] : 0.0

        let clampedHour = max(7.0, min(22.0, h))
        let plannedStartPx = (clampedHour - 7.0) * 60.0 + (m / 60.0) * 60.0
        let plannedDurationPx = (todo.plannedDuration / 3600.0) * 60.0
        let plannedEndPx = plannedStartPx + plannedDurationPx

        let isTargetToday = Calendar.current.isDateInToday(targetDate)
        let isUnstarted = todo.status == .pending

        var topPx = plannedStartPx
        var heightPx = max(38.0, plannedDurationPx)
        var isPushed = false
        var compressedMinutes = Int(todo.plannedDuration / 60.0)

        if isTargetToday && isUnstarted && currentTimePx > plannedStartPx {
            isPushed = true
            topPx = min(currentTimePx, plannedEndPx - 15)
            let remainingPx = max(20.0, plannedEndPx - topPx)
            heightPx = remainingPx
            compressedMinutes = max(5, Int((remainingPx / 60.0) * 60.0))
        }

        return (topPx, heightPx, isPushed, compressedMinutes)
    }

    private func updateTimeForTodo(_ todo: TodoEntry, verticalOffset: CGFloat) {
        let originalTimeStr = todo.plannedStartTime ?? "09:00"
        let parts = originalTimeStr.split(separator: ":").compactMap { Double($0) }
        let originalH = parts.first ?? 9.0
        let originalM = parts.count > 1 ? parts[1] : 0.0
        let originalTotalMin = originalH * 60.0 + originalM

        let deltaMinutes = (verticalOffset / 60.0) * 60.0
        let newTotalMin = max(7.0 * 60.0, min(22.0 * 60.0, originalTotalMin + deltaMinutes))
        let snappedMin = Int((newTotalMin / 15.0).rounded()) * 15

        let hour = snappedMin / 60
        let min = snappedMin % 60

        let formattedTime = String(format: "%02d:%02d", hour, min)

        var updated = todo
        updated.plannedStartTime = formattedTime
        if let idx = viewModel.todos.firstIndex(where: { $0.id == todo.id }) {
            viewModel.todos[idx] = updated
        }
    }
}
