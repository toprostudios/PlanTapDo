// Models.swift
import Foundation
import SwiftUI

// MARK: - Data Models

struct UserAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var email: String
    var tier: String
    var isCloudSynced: Bool
}

struct Category: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var icon: String?
    var notes: String?
    /// The default used by timed tasks in this category unless they override it.
    var notificationPreference: NotificationPreference = .none

    enum CodingKeys: String, CodingKey {
        case id, name, colorHex, icon, notes, notificationPreference
    }

    init(id: UUID, name: String, colorHex: String, icon: String?, notes: String?, notificationPreference: NotificationPreference = .none) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.notes = notes
        self.notificationPreference = notificationPreference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        notificationPreference = try container.decodeIfPresent(NotificationPreference.self, forKey: .notificationPreference) ?? .none
    }
}

enum NotificationPreference: Codable, Hashable, Identifiable {
    case none
    case atTime
    case before(minutes: Int)
    case beforeAndAtTime(minutes: Int)

    var id: String { storageValue }

    var storageValue: String {
        switch self {
        case .none: return "none"
        case .atTime: return "atTime"
        case .before(let minutes): return "before:\(minutes)"
        case .beforeAndAtTime(let minutes): return "beforeAndAtTime:\(minutes)"
        }
    }

    var label: String {
        switch self {
        case .none: return "Off"
        case .atTime: return "At start time"
        case .before(let minutes): return "\(minutes) min before"
        case .beforeAndAtTime(let minutes): return "\(minutes) min before and at start"
        }
    }

    var leadMinutes: Int? {
        switch self {
        case .before(let minutes), .beforeAndAtTime(let minutes): return minutes
        case .none, .atTime: return nil
        }
    }

    var includesAtTime: Bool {
        switch self {
        case .atTime, .beforeAndAtTime: return true
        case .none, .before: return false
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if value == "none" { self = .none; return }
        if value == "atTime" { self = .atTime; return }
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let minutes = Int(parts[1]),
              (1...10_080).contains(minutes) else {
            self = .none
            return
        }
        switch parts[0] {
        case "before":
            self = .before(minutes: minutes)
        case "beforeAndAtTime":
            self = .beforeAndAtTime(minutes: minutes)
        default:
            self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageValue)
    }
}

struct TimeSession: Identifiable, Codable, Hashable {
    let id: UUID
    var todoId: UUID?
    let start: Date
    var end: Date?
    var duration: TimeInterval? // seconds

    enum CodingKeys: String, CodingKey {
        case id
        case todoId = "todo"
        case start
        case end
        case duration
    }

    init(
        id: UUID,
        todoId: UUID? = nil,
        start: Date,
        end: Date?,
        duration: TimeInterval?
    ) {
        self.id = id
        self.todoId = todoId
        self.start = start
        self.end = end
        self.duration = duration
    }
}

struct Subtask: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case completed
        case isCompleted
    }

    init(id: String, title: String, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .completed)
            ?? container.decodeIfPresent(Bool.self, forKey: .isCompleted)
            ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(isCompleted, forKey: .completed)
    }
}

enum PriorityLevel: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case urgent

    var id: String { rawValue }

    var badgeText: String {
        switch self {
        case .urgent: return "🔥 URGENT"
        case .high: return "⚡ HIGH"
        case .medium: return "🔹 MED"
        case .low: return "🟢 LOW"
        }
    }
}

enum TodoStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case archived
    case skipped
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case none
    case daily
    case weekly
    case monthly
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Does not repeat"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .custom: return "Custom"
        }
    }
}

struct FocusBlock: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var weekdays: Set<Int> // Calendar weekday values, 1 = Sunday
    var startMinutes: Int
    var endMinutes: Int
    var categoryId: UUID?
    /// Empty means every category is pushed. Otherwise only these categories may stay in focus time.
    var allowedCategoryIds: Set<UUID> = []

    init(id: UUID = UUID(), name: String = "Focus time", weekdays: Set<Int>, startMinutes: Int, endMinutes: Int, categoryId: UUID? = nil) {
        self.id = id
        self.name = name
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.categoryId = categoryId
    }

    init(id: UUID = UUID(), name: String = "Focus time", weekdays: Set<Int>, startMinutes: Int, endMinutes: Int, allowedCategoryIds: Set<UUID>) {
        self.id = id
        self.name = name
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.categoryId = nil
        self.allowedCategoryIds = allowedCategoryIds
    }

    enum CodingKeys: String, CodingKey {
        case id, name, weekdays, startMinutes, endMinutes, categoryId, allowedCategoryIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Focus time"
        weekdays = try container.decode(Set<Int>.self, forKey: .weekdays)
        startMinutes = try container.decode(Int.self, forKey: .startMinutes)
        endMinutes = try container.decode(Int.self, forKey: .endMinutes)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        allowedCategoryIds = try container.decodeIfPresent(Set<UUID>.self, forKey: .allowedCategoryIds) ?? []
    }
}

struct TodoEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String?
    var doDate: Date             // Date scheduled to do it
    var dueDate: Date?           // Deadline date
    var dueTime: String?         // HH:MM (e.g. "18:00")
    var descriptiveDeadline: String? // Descriptive deadline note (no effect on calendar position)
    var plannedStartTime: String? // HH:MM (e.g. "09:30")
    /// The user-set earliest date and time for this task. Automatic reflows may
    /// move it later, but never earlier than this point.
    var scheduledNotBefore: Date?
    /// Seconds. Zero means the estimate is unspecified (a five-minute default
    /// is used outside the calendar).
    var plannedDuration: TimeInterval
    /// User-controlled order for task-list views. Zero is the legacy/default
    /// value, which keeps the time-and-title ordering until a list is reordered.
    var sortOrder: Int
    var categoryId: UUID?
    var status: TodoStatus
    var priority: PriorityLevel?
    var location: String?
    var reminder: String?
    /// Nil means use the category's default. A concrete value, including `.none`, overrides it.
    var notificationPreference: NotificationPreference?
    var labels: [String]?
    var timeSessions: [TimeSession]?
    var subtasks: [Subtask]?
    var assigneeId: String?
    var recurrenceFrequency: RecurrenceFrequency
    var recurrenceWeekdays: [Int]?
    var recurrenceSeriesId: UUID?
    var completedAt: Date?
    /// When automatic reflow spills a task over Off Time, this identifies the
    /// generated next-day piece. It is rebuilt on each reflow, never a second
    /// user-created task.
    var splitParentID: UUID?
    /// The parent's full estimate while its visible card is temporarily
    /// shortened to the portion that still fits before Off Time.
    var splitOriginalDuration: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case doDate
        case dueDate
        case dueTime
        case descriptiveDeadline
        case plannedStartTime
        case scheduledNotBefore
        case plannedDuration
        case sortOrder
        case categoryId
        case status
        case priority
        case location
        case reminder
        case notificationPreference
        case labels
        case subtasks
        case assigneeId
        case recurrenceFrequency
        case recurrenceWeekdays
        case recurrenceSeriesId
        case completedAt
        case splitParentID
        case splitOriginalDuration
    }

    init(
        id: UUID,
        title: String,
        description: String?,
        doDate: Date,
        dueDate: Date?,
        dueTime: String?,
        descriptiveDeadline: String?,
        plannedStartTime: String?,
        plannedDuration: TimeInterval,
        sortOrder: Int = 0,
        categoryId: UUID?,
        status: TodoStatus,
        priority: PriorityLevel?,
        location: String?,
        reminder: String?,
        notificationPreference: NotificationPreference? = nil,
        labels: [String]?,
        timeSessions: [TimeSession]?,
        subtasks: [Subtask]?,
        assigneeId: String?,
        recurrenceFrequency: RecurrenceFrequency = .none,
        recurrenceWeekdays: [Int]? = nil,
        recurrenceSeriesId: UUID? = nil,
        completedAt: Date? = nil,
        scheduledNotBefore: Date? = nil,
        splitParentID: UUID? = nil,
        splitOriginalDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.doDate = doDate
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.descriptiveDeadline = descriptiveDeadline
        self.plannedStartTime = plannedStartTime
        self.scheduledNotBefore = scheduledNotBefore
        self.plannedDuration = plannedDuration
        self.sortOrder = sortOrder
        self.categoryId = categoryId
        self.status = status
        self.priority = priority
        self.location = location
        self.reminder = reminder
        self.notificationPreference = notificationPreference
        self.labels = labels
        self.timeSessions = timeSessions
        self.subtasks = subtasks
        self.assigneeId = assigneeId
        self.recurrenceFrequency = recurrenceFrequency
        self.recurrenceWeekdays = recurrenceWeekdays
        self.recurrenceSeriesId = recurrenceSeriesId
        self.completedAt = completedAt
        self.splitParentID = splitParentID
        self.splitOriginalDuration = splitOriginalDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        doDate = Self.decodeDate(from: container, forKey: .doDate)
            ?? Calendar.current.startOfDay(for: Date())
        dueDate = Self.decodeDate(from: container, forKey: .dueDate)
        dueTime = try container.decodeIfPresent(String.self, forKey: .dueTime)
        descriptiveDeadline = try container.decodeIfPresent(String.self, forKey: .descriptiveDeadline)
        plannedStartTime = try container.decodeIfPresent(String.self, forKey: .plannedStartTime)
        scheduledNotBefore = Self.decodeDate(from: container, forKey: .scheduledNotBefore)

        let durationMinutes = try container.decodeIfPresent(Double.self, forKey: .plannedDuration) ?? 30
        plannedDuration = durationMinutes * 60
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0

        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        status = try container.decodeIfPresent(TodoStatus.self, forKey: .status) ?? .pending
        priority = try container.decodeIfPresent(PriorityLevel.self, forKey: .priority)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        reminder = try container.decodeIfPresent(String.self, forKey: .reminder)
        notificationPreference = try container.decodeIfPresent(NotificationPreference.self, forKey: .notificationPreference)
        labels = try container.decodeIfPresent([String].self, forKey: .labels)
        timeSessions = nil
        subtasks = try container.decodeIfPresent([Subtask].self, forKey: .subtasks)
        assigneeId = try container.decodeIfPresent(String.self, forKey: .assigneeId)
        recurrenceFrequency = try container.decodeIfPresent(RecurrenceFrequency.self, forKey: .recurrenceFrequency) ?? .none
        recurrenceWeekdays = try container.decodeIfPresent([Int].self, forKey: .recurrenceWeekdays)
        recurrenceSeriesId = try container.decodeIfPresent(UUID.self, forKey: .recurrenceSeriesId)
        completedAt = Self.decodeDate(from: container, forKey: .completedAt)
        splitParentID = try container.decodeIfPresent(UUID.self, forKey: .splitParentID)
        if let splitMinutes = try container.decodeIfPresent(Double.self, forKey: .splitOriginalDuration) {
            splitOriginalDuration = splitMinutes * 60
        } else {
            splitOriginalDuration = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(Self.apiDateString(from: doDate), forKey: .doDate)
        if let dueDate {
            try container.encode(Self.apiDateString(from: dueDate), forKey: .dueDate)
        } else {
            try container.encodeNil(forKey: .dueDate)
        }
        try container.encode(dueTime, forKey: .dueTime)
        try container.encode(descriptiveDeadline, forKey: .descriptiveDeadline)
        try container.encode(plannedStartTime, forKey: .plannedStartTime)
        if let scheduledNotBefore {
            try container.encode(Self.apiDateTimeString(from: scheduledNotBefore), forKey: .scheduledNotBefore)
        } else {
            try container.encodeNil(forKey: .scheduledNotBefore)
        }
        try container.encode(max(0, Int((plannedDuration / 60).rounded())), forKey: .plannedDuration)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encode(location, forKey: .location)
        try container.encode(reminder, forKey: .reminder)
        try container.encodeIfPresent(notificationPreference, forKey: .notificationPreference)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(subtasks, forKey: .subtasks)
        try container.encode(assigneeId, forKey: .assigneeId)
        try container.encode(recurrenceFrequency, forKey: .recurrenceFrequency)
        try container.encodeIfPresent(recurrenceWeekdays, forKey: .recurrenceWeekdays)
        try container.encode(recurrenceSeriesId, forKey: .recurrenceSeriesId)
        if let completedAt {
            try container.encode(Self.apiDateTimeString(from: completedAt), forKey: .completedAt)
        } else {
            try container.encodeNil(forKey: .completedAt)
        }
        try container.encodeIfPresent(splitParentID, forKey: .splitParentID)
        if let splitOriginalDuration {
            try container.encode(max(0, Int((splitOriginalDuration / 60).rounded())), forKey: .splitOriginalDuration)
        } else {
            try container.encodeNil(forKey: .splitOriginalDuration)
        }
    }

    private static func decodeDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        guard let value = try? container.decode(String.self, forKey: key) else {
            return nil
        }
        return apiDate(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func apiDateTimeString(from date: Date) -> String {
        // Foundation formatters have mutable internal state and are not
        // Sendable. A fresh formatter avoids races between background API
        // decoding and main-thread local persistence.
        ISO8601DateFormatter().string(from: date)
    }

    /// Django's date fields represent a calendar day without a time zone. Build
    /// them with the device's current calendar at the moment of conversion so a
    /// cached formatter cannot shift the task across days after a time-zone change.
    static func apiDate(
        from value: String,
        in timeZone: TimeZone = .autoupdatingCurrent
    ) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return nil
        }
        let decoded = calendar.dateComponents([.year, .month, .day], from: date)
        guard decoded.year == year, decoded.month == month, decoded.day == day else {
            return nil
        }
        return date
    }

    private static func apiDateString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func apiTimeString(from date: Date) -> String {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case dark = "Dark"
    case light = "Light"

    var id: String { rawValue }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }
}

// MARK: - Color Hex Extension (Global across iOS project)
extension Color {
    init(hex: String) {
        let hexClean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexClean).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
