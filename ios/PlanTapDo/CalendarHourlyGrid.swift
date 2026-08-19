// CalendarHourlyGrid.swift
import SwiftUI

struct CalendarHourlyGrid: View {
    @ObservedObject var viewModel: TodoViewModel
    let date: Date
    var onOpenTask: (TodoEntry) -> Void = { _ in }
    var showsTodayBadge = true
    @State private var showingCalendarAdd = false
    @State private var draftStart = Date()

    private let hours = Array(7...22) // 7 AM to 10 PM
    @State private var now = Date()
    @State private var draggingTodoId: UUID? = nil
    @State private var dragYTranslation: CGFloat = 0
    @State private var calendarScale: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1
    @State private var calendarSpan = 1

    private let baseHourHeight: CGFloat = 60

    private var effectiveCalendarScale: CGFloat {
        min(max(calendarScale * pinchScale, 0.6), 1.8)
    }

    private var hourHeight: CGFloat {
        baseHourHeight * effectiveCalendarScale
    }

    private var pointsPerMinute: CGFloat {
        hourHeight / 60
    }

    private var visibleDates: [Date] {
        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: date)

        switch calendarSpan {
        case 3:
            return (0..<3).compactMap { calendar.date(byAdding: .day, value: $0, to: baseDate) }
        case 7:
            let weekday = calendar.component(.weekday, from: baseDate)
            let daysToMonday = weekday == 1 ? -6 : 2 - weekday
            guard let monday = calendar.date(byAdding: .day, value: daysToMonday, to: baseDate) else { return [] }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
        default:
            return [baseDate]
        }
    }

    private func category(for catId: UUID?) -> Category? {
        guard let catId = catId else { return nil }
        return viewModel.categories.first { $0.id == catId }
    }

    private var currentTimePx: CGFloat {
        let h = CGFloat(Calendar.current.component(.hour, from: now))
        let m = CGFloat(Calendar.current.component(.minute, from: now))
        let s = CGFloat(Calendar.current.component(.second, from: now))
        return ((h - 7.0) * 60.0 + m + (s / 60.0)) * pointsPerMinute
    }

    private func dayTodos(for targetDate: Date) -> [TodoEntry] {
        let calendar = Calendar.current
        return viewModel.todos.filter {
            calendar.isDate($0.doDate, inSameDayAs: targetDate)
                && $0.plannedStartTime?.isEmpty == false
                && $0.status != .completed
                && $0.status != .archived
                && $0.status != .skipped
        }
            .sorted { ($0.plannedStartTime ?? "23:59") < ($1.plannedStartTime ?? "23:59") }
    }

    private func historyTodos(for targetDate: Date) -> [TodoEntry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: targetDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return viewModel.todos.filter { todo in
            (todo.timeSessions ?? []).contains { session in
                let sessionEnd = session.end ?? now
                return session.start < dayEnd && sessionEnd > dayStart
            }
        }
    }

    private func plannedHistoryTodos(for targetDate: Date) -> [TodoEntry] {
        let calendar = Calendar.current
        return viewModel.todos.filter {
            (calendar.isDate($0.doDate, inSameDayAs: targetDate)
                || ($0.overdueFromDate.map { calendar.isDate($0, inSameDayAs: targetDate) } ?? false))
                && $0.plannedStartTime?.isEmpty == false
                && $0.originalPlannedStartTime != nil
                && $0.originalPlannedStartTime != $0.plannedStartTime
        }
    }

    private func focusBlocks(for targetDate: Date) -> [FocusBlock] {
        let weekday = Calendar.current.component(.weekday, from: targetDate)
        return viewModel.focusBlocks.filter { $0.weekdays.contains(weekday) }
    }

    private func focusBlockMetrics(for block: FocusBlock) -> (top: CGFloat, height: CGFloat)? {
        let gridStart = 7 * 60
        let gridEnd = 23 * 60
        let start = max(gridStart, block.startMinutes)
        let end = min(gridEnd, block.endMinutes)
        guard end > start else { return nil }
        return (CGFloat(start - gridStart) * pointsPerMinute, CGFloat(end - start) * pointsPerMinute)
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
                let topPx = CGFloat(endMinA - 7.0 * 60.0) * pointsPerMinute
                let heightPx = max(20 * effectiveCalendarScale, CGFloat(duration) * pointsPerMinute)

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
            let totalAvailableWidth = max(320, outerGeo.size.width)
            // Keep labels like “1:00 PM” comfortably inside the visible rail.
            let timeColWidth: CGFloat = 58
            let gridWidth = totalAvailableWidth - timeColWidth

            let calculatedColWidth = max(1, gridWidth / CGFloat(max(1, visibleDates.count)))

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Label("Planned", systemImage: "square.dashed")
                        .foregroundStyle(.secondary)
                    Label("Actual", systemImage: "square.fill")
                        .foregroundStyle(.indigo)
                    Label("Unplanned", systemImage: "square.fill")
                        .foregroundStyle(.black)
                }
                .font(.system(size: 9, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)

                Picker("Calendar range", selection: $calendarSpan) {
                    Text("1 day").tag(1)
                    Text("3 days").tag(3)
                    Text("Week").tag(7)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
                        // Hour Grid Lines & Labels Column
                        VStack(spacing: 0) {
                            Text("Time")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 8)
                                .frame(height: 28)

                            ForEach(hours, id: \.self) { hour in
                                HStack(alignment: .top) {
                                    Text(formatHour(hour))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .padding(.trailing, 8)
                                }
                                .frame(height: hourHeight)
                            }
                        }
                        .frame(width: timeColWidth)

                        // Multi-Day Columns
                        HStack(spacing: 0) {
                            ForEach(visibleDates, id: \.self) { colDate in
                                let isCompactLayout = visibleDates.count > 3
                                let todosForDay = dayTodos(for: colDate)
                                let historyTodosForDay = historyTodos(for: colDate)
                                let focusBlocksForDay = focusBlocks(for: colDate)
                                let overlapMap = computeOverlapLayouts(for: colDate)
                                let transportBlocks = computeTransportBlocks(for: colDate)
                                let isColToday = Calendar.current.isDateInToday(colDate)
                                let formattedDateStr = isCompactLayout
                                    ? colDate.formatted(.dateTime.weekday(.narrow).day())
                                    : colDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())

                                VStack(spacing: 0) {
                                    // Column Day Header
                                    HStack(spacing: 4) {
                                        Text(formattedDateStr)
                                            .font(.system(size: isCompactLayout ? 8 : 10, weight: .bold))
                                            .foregroundStyle(isColToday ? Color.indigo : Color.primary)
                                            .lineLimit(1)
                                        if showsTodayBadge && isColToday && !isCompactLayout {
                                            Text("TODAY")
                                                .font(.system(size: 7, weight: .black))
                                                .padding(.horizontal, 3)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(Color.indigo))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(height: 28)
                                    .frame(maxWidth: .infinity)
                                    .background(isColToday ? Color.indigo.opacity(0.1) : Color.secondary.opacity(0.06))
                                    .border(Color.secondary.opacity(0.15), width: 0.5)

                                    // Hour Grid Lines & Task Cards Container
                                    GeometryReader { geo in
                                        ZStack(alignment: .topLeading) {
                                            // Blocked time is a background layer; allowed category tasks remain above it.
                                            ForEach(focusBlocksForDay) { block in
                                                if let metrics = focusBlockMetrics(for: block) {
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .fill(Color.indigo.opacity(0.12))
                                                        .overlay {
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .stroke(Color.indigo.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                                        }
                                                        .frame(width: max(35, geo.size.width - 6), height: metrics.height)
                                                        .overlay(alignment: .topLeading) {
                                                            HStack(spacing: 3) {
                                                                Image(systemName: "lock.fill")
                                                                Text(block.name.uppercased())
                                                            }
                                                            .font(.system(size: 8, weight: .black))
                                                            .foregroundStyle(Color.indigo)
                                                            .padding(5)
                                                        }
                                                        .offset(x: 3, y: metrics.top)
                                                }
                                            }

                                            // Grid lines
                                            VStack(spacing: 0) {
                                                ForEach(hours, id: \.self) { _ in
                                                    VStack {
                                                        Divider()
                                                        Spacer()
                                                    }
                                                    .frame(height: hourHeight)
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
                                                        .zIndex(3)
                                                }
                                            }

                                            // Original schedule remains visible after a task is pushed or dragged.
                                            ForEach(plannedHistoryTodos(for: colDate)) { todo in
                                                if let history = plannedHistoryMetrics(for: todo) {
                                                    let historyColor = Color(hex: category(for: todo.categoryId)?.colorHex ?? "7C6FF7")
                                                    RoundedRectangle(cornerRadius: 7)
                                                        .fill(historyColor.opacity(0.35))
                                                        .overlay {
                                                            RoundedRectangle(cornerRadius: 7)
                                                                .stroke(historyColor.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                                        }
                                                        .frame(width: max(35, geo.size.width - 4), height: history.height)
                                                        .overlay(alignment: .topLeading) {
                                                            if !isCompactLayout && geo.size.width >= 105 {
                                                                Text("PLANNED WORK")
                                                                    .font(.system(size: 7, weight: .black))
                                                                    .foregroundStyle(historyColor)
                                                                    .padding(4)
                                                            }
                                                        }
                                                        .offset(x: 2, y: history.top)
                                                        .zIndex(0)
                                                }
                                            }

                                            // Recorded timer sessions are the solid history laid over the plan.
                                            ForEach(historyTodosForDay) { todo in
                                                ForEach(todo.timeSessions ?? []) { session in
                                                    if let actual = actualSessionMetrics(for: session, on: colDate) {
                                                        let sessionColor = actualSessionColor(for: todo)
                                                        RoundedRectangle(cornerRadius: 5)
                                                            .fill(sessionColor.opacity(0.88))
                                                            .frame(width: max(25, geo.size.width - 10), height: actual.height)
                                                            .overlay(alignment: .topLeading) {
                                                                if !isCompactLayout && geo.size.width >= 105 {
                                                                    Text("ACTUAL WORK")
                                                                        .font(.system(size: 7, weight: .black))
                                                                        .foregroundStyle(.white)
                                                                        .padding(3)
                                                                }
                                                            }
                                                            .offset(x: 5, y: actual.top)
                                                            .zIndex(1)
                                                    }
                                                }
                                            }

                                            // Render Transport Time Blocks
                                            ForEach(transportBlocks, id: \.id) { tb in
                                                Group {
                                                    if !isCompactLayout && geo.size.width >= 105 {
                                                        HStack(spacing: 2) {
                                                            Text("🚗").font(.system(size: 9))
                                                            Text("\(tb.duration)m: \(tb.from) ➔ \(tb.to)")
                                                                .font(.system(size: 8, weight: .bold))
                                                                .foregroundStyle(.orange)
                                                                .lineLimit(1)
                                                        }
                                                        .padding(.horizontal, 4)
                                                    }
                                                }
                                                .frame(width: max(35, geo.size.width - 4), height: tb.height, alignment: .leading)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(Color.orange.opacity(0.18))
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [3]))
                                                )
                                                .offset(x: 2, y: tb.top)
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
                                                    isCompact: isCompactLayout,
                                                    onOpen: { onOpenTask(todo) },
                                                    onDragChanged: { offset in
                                                        draggingTodoId = todo.id
                                                        dragYTranslation = offset
                                                    },
                                                    onDragEnded: { offset in
                                                        draggingTodoId = nil
                                                        dragYTranslation = 0
                                                        updateTimeForTodo(todo, verticalOffset: offset)
                                                    },
                                                    onDragCancelled: {
                                                        // A cancelled gesture has no valid drop. Restore the card
                                                        // at its stored position instead of leaving its visual offset.
                                                        draggingTodoId = nil
                                                        dragYTranslation = 0
                                                    }
                                                )
                                                .zIndex(2)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .gesture(SpatialTapGesture().onEnded { value in
                                            guard value.location.x > 0 else { return }
                                            let minute = max(7 * 60, min(22 * 60, 7 * 60 + Int((value.location.y / hourHeight).rounded()) * 60))
                                            draftStart = Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: colDate) ?? colDate
                                            showingCalendarAdd = true
                                        }, including: .gesture)
                                    }
                                    .frame(height: CGFloat(hours.count) * hourHeight)
                                }
                                .frame(width: calculatedColWidth)
                                .border(Color.secondary.opacity(0.15), width: 0.5)
                            }
                        }
                    }
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .updating($pinchScale) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            calendarScale = min(max(calendarScale * value, 0.6), 1.8)
                        }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.02))
        }
        .onAppear {
            now = Date()
            viewModel.pushOverdueTasks(at: now)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { input in
            now = input
            if Calendar.current.component(.second, from: input) == 0 {
                viewModel.pushOverdueTasks(at: input)
            }
        }
        .sheet(isPresented: $showingCalendarAdd) {
            TaskComposerView(viewModel: viewModel, start: draftStart)
                .presentationDetents([.large])
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h):00 \(period)"
    }

    private func getPushedMetrics(for todo: TodoEntry, targetDate: Date) -> (top: CGFloat, height: CGFloat, isPushed: Bool, compressedMinutes: Int) {
        guard let timeStr = todo.plannedStartTime else {
            return (0, 0, false, 0)
        }
        let parts = timeStr.split(separator: ":").compactMap { Double($0) }
        let h = parts.first ?? 9.0
        let m = parts.count > 1 ? parts[1] : 0.0

        let clampedHour = max(7.0, min(22.0, h))
        let plannedStartPx = ((clampedHour - 7.0) * 60.0 + m) * pointsPerMinute
        let plannedDurationPx = CGFloat(todo.plannedDuration / 60.0) * pointsPerMinute
        let heightPx = max(52 * effectiveCalendarScale, plannedDurationPx)
        let plannedMinutes = Int(todo.plannedDuration / 60.0)
        let isPushed = todo.originalPlannedStartTime != nil
            && todo.originalPlannedStartTime != todo.plannedStartTime

        return (plannedStartPx, heightPx, isPushed, plannedMinutes)
    }

    private func plannedHistoryMetrics(for todo: TodoEntry) -> (top: CGFloat, height: CGFloat)? {
        guard let time = todo.originalPlannedStartTime ?? todo.plannedStartTime else { return nil }
        let start = CGFloat(Self.minutes(from: time) - 7 * 60) * pointsPerMinute
        let height = max(12 * effectiveCalendarScale, CGFloat(todo.plannedDuration / 60) * pointsPerMinute)
        return (max(0, start), height)
    }

    private func actualSessionMetrics(for session: TimeSession, on targetDate: Date) -> (top: CGFloat, height: CGFloat)? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: targetDate)
        guard let gridStart = calendar.date(byAdding: .hour, value: 7, to: dayStart),
              let gridEnd = calendar.date(byAdding: .hour, value: 23, to: dayStart) else { return nil }

        let sessionEnd = session.end ?? now
        let clippedStart = max(session.start, gridStart)
        let clippedEnd = min(sessionEnd, gridEnd)
        guard clippedEnd > clippedStart else { return nil }

        let top = CGFloat(clippedStart.timeIntervalSince(gridStart) / 60) * pointsPerMinute
        let height = max(4 * effectiveCalendarScale, CGFloat(clippedEnd.timeIntervalSince(clippedStart) / 60) * pointsPerMinute)
        return (top, height)
    }

    private func actualSessionColor(for todo: TodoEntry) -> Color {
        guard todo.originalPlannedStartTime != nil else { return .black }
        return Color(hex: category(for: todo.categoryId)?.colorHex ?? "7C6FF7")
    }

    private func updateTimeForTodo(_ todo: TodoEntry, verticalOffset: CGFloat) {
        let originalTimeStr = todo.plannedStartTime ?? "09:00"
        let parts = originalTimeStr.split(separator: ":").compactMap { Double($0) }
        let originalH = parts.first ?? 9.0
        let originalM = parts.count > 1 ? parts[1] : 0.0
        let originalTotalMin = originalH * 60.0 + originalM

        let deltaMinutes = Double(verticalOffset / pointsPerMinute)
        let proposedTotalMin = originalTotalMin + deltaMinutes

        // Releasing outside the visible calendar is not a schedule change. In
        // particular, this keeps a card from appearing to disappear after an
        // incomplete drag beyond the top or bottom edge.
        guard proposedTotalMin >= 7.0 * 60.0, proposedTotalMin <= 22.0 * 60.0 else {
            return
        }

        let newTotalMin = proposedTotalMin
        var snappedMin = Int((newTotalMin / 15.0).rounded()) * 15

        // A pending task may not be dragged into the past. Keeping it at the current
        // five-minute slot prevents the live scheduler from immediately moving it again.
        if Calendar.current.isDateInToday(todo.doDate), todo.status == .pending {
            let calendar = Calendar.current
            let nowMinutes = calendar.component(.hour, from: now) * 60
                + calendar.component(.minute, from: now)
            let currentSlot = Int(ceil(Double(nowMinutes) / 5.0) * 5.0)
            snappedMin = max(snappedMin, currentSlot)
        }

        snappedMin = max(7 * 60, min(22 * 60, snappedMin))

        let hour = snappedMin / 60
        let min = snappedMin % 60

        let formattedTime = String(format: "%02d:%02d", hour, min)

        var updated = todo
        updated.doDate = todo.doDate
        updated.plannedStartTime = formattedTime
        viewModel.updateTodo(updated)
    }

    private static func minutes(from time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 9 * 60 }
        return parts[0] * 60 + parts[1]
    }
}

struct TaskComposerView: View {
    @ObservedObject var viewModel: TodoViewModel
    let start: Date
    let showsSchedule: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var startDate: Date
    @State private var duration = 30
    @State private var categoryId: UUID?

    init(viewModel: TodoViewModel, start: Date, showsSchedule: Bool = true) {
        self.viewModel = viewModel
        self.start = start
        self.showsSchedule = showsSchedule
        _startDate = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(showsSchedule ? "Plan something ahead" : "What needs doing today?")
                            .font(.title2.weight(.bold))
                        Text(showsSchedule ? "Give it a time, then make it happen." : "Capture it now — you can schedule it later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        TextField("Task name", text: $title)
                            .font(.headline)
                            .textFieldStyle(.plain)
                            .padding(16)
                        Divider()
                        TextField("Add notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(2...5)
                            .textFieldStyle(.plain)
                            .padding(16)
                    }
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.thinMaterial))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                    if showsSchedule {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Schedule", systemImage: "calendar")
                                .font(.headline)

                            DatePicker("Starts", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Duration")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                                        Button(durationLabel(minutes)) { duration = minutes }
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(duration == minutes ? .white : .primary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(
                                                Capsule().fill(duration == minutes ? Color.indigo : Color.secondary.opacity(0.12))
                                            )
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemGroupedBackground)))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Category", systemImage: "tag")
                            .font(.headline)
                        Picker("Category", selection: $categoryId) {
                            Text("No category").tag(UUID?.none)
                            ForEach(viewModel.categories) { category in
                                Text("\(category.icon ?? "🔖") \(category.name)").tag(Optional(category.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.06)))
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemGroupedBackground)))

                    Button(action: add) {
                        Label("Add task", systemImage: "plus")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Capsule().fill(Color.indigo))
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
    }

    private func add() {
        viewModel.createTodo(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: notes.isEmpty ? nil : notes,
            doDate: startDate,
            plannedStartTime: showsSchedule ? TodoEntry.apiTimeString(from: startDate) : nil,
            plannedDuration: TimeInterval(duration * 60),
            categoryId: categoryId
        )
        dismiss()
    }
}

// MARK: - Extracted Card View Subview for Fast Swift Compilation
struct CalendarCardView: View {
    let todo: TodoEntry
    let metrics: (top: CGFloat, height: CGFloat, isPushed: Bool, compressedMinutes: Int)
    let cat: Category?
    let layout: (colIndex: Int, totalCols: Int)
    let containerWidth: CGFloat
    let draggingTodoId: UUID?
    let dragYTranslation: CGFloat
    @ObservedObject var viewModel: TodoViewModel
    let isCompact: Bool
    let onOpen: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void
    let onDragCancelled: () -> Void
    @GestureState private var isDragActive = false

    private var catColor: Color {
        Color(hex: cat?.colorHex ?? "7C6FF7")
    }

    private var isTimerActive: Bool {
        viewModel.activeTimerTodoId == todo.id
    }

    private var taskFont: Font {
        .system(size: isCompact ? 8 : 10, weight: .bold)
    }

    var body: some View {
        let colWidth = containerWidth / CGFloat(layout.totalCols)
        let leftOffset = CGFloat(layout.colIndex) * colWidth
        let currentDragOffset = (draggingTodoId == todo.id) ? dragYTranslation : 0
        let showsCardText = !isCompact && colWidth >= 88

        HStack(alignment: .top, spacing: 5) {
            if showsCardText {
                Button {
                    viewModel.toggleComplete(todo)
                } label: {
                    Image(systemName: "circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(catColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Finish \(todo.title)")
            }

            if showsCardText {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 3) {
                            if let icon = cat?.icon {
                                Text(icon).font(.system(size: 10))
                            }

                            Text(todo.title)
                                .font(taskFont)
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }

                        Text(todo.plannedStartTime ?? "")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.86))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onOpen) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }

            if todo.status != .completed && showsCardText && containerWidth >= 100 {
                Button {
                    if isTimerActive {
                        viewModel.stopTimer()
                    } else {
                        viewModel.startTimer(for: todo)
                    }
                } label: {
                    Image(systemName: isTimerActive ? "stop.fill" : "play.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(isTimerActive ? Color.red : Color.indigo))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(metrics.isPushed ? catColor.opacity(0.58) : catColor)
        )
        .overlay(
            Rectangle()
                .fill(catColor)
                .frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: max(45, colWidth - 4), height: metrics.height, alignment: .topLeading)
        .offset(x: leftOffset + 2, y: metrics.top + currentDragOffset)
        .animation(.linear(duration: 0.2), value: metrics.top)
        .gesture(
            DragGesture()
                .updating($isDragActive) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    onDragChanged(value.translation.height)
                }
                .onEnded { value in
                    onDragEnded(value.translation.height)
                }
        )
        .onChange(of: isDragActive) { isActive in
            // GestureState resets to false both after a normal end and when the
            // parent scroll view cancels the drag. This cleanup is intentionally
            // save-free, so only onEnded can move a task.
            if !isActive {
                onDragCancelled()
            }
        }
    }
}
