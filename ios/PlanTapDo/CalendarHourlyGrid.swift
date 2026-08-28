// CalendarHourlyGrid.swift
import SwiftUI

struct CalendarOverlapLayout {
    static func compute(
        for todos: [TodoEntry]
    ) -> [UUID: (colIndex: Int, totalCols: Int)] {
        struct Interval {
            let id: UUID
            let start: Double
            let end: Double
        }

        let intervals = todos.map { todo -> Interval in
            let parts = (todo.plannedStartTime ?? "09:00")
                .split(separator: ":")
                .compactMap { Double($0) }
            let start = (parts.first ?? 9) * 60 + (parts.count > 1 ? parts[1] : 0)
            return Interval(
                id: todo.id,
                start: start,
                // Cards have a 52-point minimum height, equivalent to 52
                // minutes at every zoom level. Use that rendered footprint so
                // short adjacent tasks do not visually collide in one lane.
                end: start + max(52, todo.plannedDuration / 60)
            )
        }
        .sorted {
            if $0.start == $1.start { return $0.id.uuidString < $1.id.uuidString }
            return $0.start < $1.start
        }

        var result: [UUID: (colIndex: Int, totalCols: Int)] = [:]

        func assignLanes(to cluster: [Interval]) {
            var laneEnds: [Double] = []
            var laneByID: [UUID: Int] = [:]

            for interval in cluster {
                if let availableLane = laneEnds.firstIndex(where: { $0 <= interval.start }) {
                    laneEnds[availableLane] = interval.end
                    laneByID[interval.id] = availableLane
                } else {
                    laneByID[interval.id] = laneEnds.count
                    laneEnds.append(interval.end)
                }
            }

            let totalColumns = max(1, laneEnds.count)
            for interval in cluster {
                result[interval.id] = (laneByID[interval.id] ?? 0, totalColumns)
            }
        }

        var cluster: [Interval] = []
        var clusterEnd = -Double.infinity
        for interval in intervals {
            if !cluster.isEmpty, interval.start >= clusterEnd {
                assignLanes(to: cluster)
                cluster.removeAll(keepingCapacity: true)
                clusterEnd = -Double.infinity
            }
            cluster.append(interval)
            clusterEnd = max(clusterEnd, interval.end)
        }
        if !cluster.isEmpty {
            assignLanes(to: cluster)
        }
        return result
    }
}

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
        return ((h - 7.0) * 60.0 + m) * pointsPerMinute
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
        CalendarOverlapLayout.compute(for: dayTodos(for: targetDate))
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
                    Label("Schedule", systemImage: "calendar")
                        .foregroundStyle(.secondary)
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
                                            let minute = max(7 * 60, min(22 * 60 + 59, 7 * 60 + Int((value.location.y / pointsPerMinute).rounded())))
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
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { input in
            now = input
            viewModel.pushOverdueTasks(at: input)
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
        // Depend on the stopwatch so an active card grows smoothly instead of
        // leaving a second "actual work" block beneath the task.
        let _ = viewModel.timerSecondsElapsed
        let plannedDurationPx = CGFloat(viewModel.calendarDuration(for: todo, at: Date()) / 60.0) * pointsPerMinute
        let heightPx = max(20 * effectiveCalendarScale, plannedDurationPx)
        let plannedMinutes = Int(viewModel.calendarDuration(for: todo, at: Date()) / 60.0)
        return (plannedStartPx, heightPx, false, plannedMinutes)
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
    @State private var notificationPreference: NotificationPreference?
    @State private var showingAddCategory = false

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

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Notification", systemImage: "bell")
                                .font(.headline)
                            NotificationPreferencePicker(
                                preference: $notificationPreference,
                                inheritedPreference: categoryId.flatMap { id in viewModel.categories.first { $0.id == id }?.notificationPreference },
                                allowsInheritedDefault: true
                            )
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
                            Divider()
                            Text("Add new category…").tag(Optional(Self.newCategoryOptionID))
                        }
                        .onChange(of: categoryId) { newValue in
                            guard newValue == Self.newCategoryOptionID else { return }
                            categoryId = nil
                            showingAddCategory = true
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
        .sheet(isPresented: $showingAddCategory) {
            AddCategoryView(viewModel: viewModel) { category in
                categoryId = category.id
            }
            .presentationDetents([.medium])
        }
    }

    private static let newCategoryOptionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

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
            categoryId: categoryId,
            notificationPreference: showsSchedule ? notificationPreference : nil
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
        let showsTime = showsCardText && metrics.height >= 44
        let showsControls = showsCardText && colWidth >= 190 && metrics.height >= 44
        let verticalPadding: CGFloat = metrics.height < 36 ? 2 : 6

        HStack(alignment: .top, spacing: 5) {
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
                                .lineLimit(showsTime ? 1 : 2)
                                .truncationMode(.tail)
                        }

                        if showsTime {
                            Text(isTimerActive ? viewModel.timerFormatted : (todo.plannedStartTime ?? ""))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.86))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onOpen) {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if todo.status != .completed && showsControls {
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
                .disabled(!isTimerActive && !viewModel.canStartAnotherTask)

                Button {
                    viewModel.finishTodo(id: todo.id)
                } label: {
                    Text("Finish")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(height: 28)
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Finish \(todo.title)")
            }
        }
        .padding(.vertical, verticalPadding)
        .padding(.trailing, 6)
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
