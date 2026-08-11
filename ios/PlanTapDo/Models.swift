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
    var originalPlannedStartTime: String? // Retained when the live schedule is pushed or dragged
    /// The day this task was scheduled for before it was carried into a later day.
    var overdueFromDate: Date?
    var plannedDuration: TimeInterval // seconds (e.g. 1800 for 30m)
    var categoryId: UUID?
    var status: TodoStatus
    var priority: PriorityLevel?
    var location: String?
    var reminder: String?
    var labels: [String]?
    var timeSessions: [TimeSession]?
    var subtasks: [Subtask]?
    var assigneeId: String?
    var recurrenceFrequency: RecurrenceFrequency
    var recurrenceWeekdays: [Int]?
    var recurrenceSeriesId: UUID?
    var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case doDate
        case dueDate
        case dueTime
        case descriptiveDeadline
        case plannedStartTime
        case originalPlannedStartTime
        case overdueFromDate
        case plannedDuration
        case categoryId
        case status
        case priority
        case location
        case reminder
        case labels
        case subtasks
        case assigneeId
        case recurrenceFrequency
        case recurrenceWeekdays
        case recurrenceSeriesId
        case completedAt
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
        categoryId: UUID?,
        status: TodoStatus,
        priority: PriorityLevel?,
        location: String?,
        reminder: String?,
        labels: [String]?,
        timeSessions: [TimeSession]?,
        subtasks: [Subtask]?,
        assigneeId: String?,
        originalPlannedStartTime: String? = nil,
        overdueFromDate: Date? = nil,
        recurrenceFrequency: RecurrenceFrequency = .none,
        recurrenceWeekdays: [Int]? = nil,
        recurrenceSeriesId: UUID? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.doDate = doDate
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.descriptiveDeadline = descriptiveDeadline
        self.plannedStartTime = plannedStartTime
        self.originalPlannedStartTime = originalPlannedStartTime ?? plannedStartTime
        self.overdueFromDate = overdueFromDate
        self.plannedDuration = plannedDuration
        self.categoryId = categoryId
        self.status = status
        self.priority = priority
        self.location = location
        self.reminder = reminder
        self.labels = labels
        self.timeSessions = timeSessions
        self.subtasks = subtasks
        self.assigneeId = assigneeId
        self.recurrenceFrequency = recurrenceFrequency
        self.recurrenceWeekdays = recurrenceWeekdays
        self.recurrenceSeriesId = recurrenceSeriesId
        self.completedAt = completedAt
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
        originalPlannedStartTime = try container.decodeIfPresent(String.self, forKey: .originalPlannedStartTime)
            ?? plannedStartTime
        overdueFromDate = Self.decodeDate(from: container, forKey: .overdueFromDate)

        let durationMinutes = try container.decodeIfPresent(Double.self, forKey: .plannedDuration) ?? 30
        plannedDuration = durationMinutes * 60

        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
        status = try container.decodeIfPresent(TodoStatus.self, forKey: .status) ?? .pending
        priority = try container.decodeIfPresent(PriorityLevel.self, forKey: .priority)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        reminder = try container.decodeIfPresent(String.self, forKey: .reminder)
        labels = try container.decodeIfPresent([String].self, forKey: .labels)
        timeSessions = nil
        subtasks = try container.decodeIfPresent([Subtask].self, forKey: .subtasks)
        assigneeId = try container.decodeIfPresent(String.self, forKey: .assigneeId)
        recurrenceFrequency = try container.decodeIfPresent(RecurrenceFrequency.self, forKey: .recurrenceFrequency) ?? .none
        recurrenceWeekdays = try container.decodeIfPresent([Int].self, forKey: .recurrenceWeekdays)
        recurrenceSeriesId = try container.decodeIfPresent(UUID.self, forKey: .recurrenceSeriesId)
        completedAt = Self.decodeDate(from: container, forKey: .completedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(Self.apiDateFormatter.string(from: doDate), forKey: .doDate)
        if let dueDate {
            try container.encode(Self.apiDateFormatter.string(from: dueDate), forKey: .dueDate)
        } else {
            try container.encodeNil(forKey: .dueDate)
        }
        try container.encode(dueTime, forKey: .dueTime)
        try container.encode(descriptiveDeadline, forKey: .descriptiveDeadline)
        try container.encode(plannedStartTime, forKey: .plannedStartTime)
        try container.encode(originalPlannedStartTime, forKey: .originalPlannedStartTime)
        if let overdueFromDate {
            try container.encode(Self.apiDateFormatter.string(from: overdueFromDate), forKey: .overdueFromDate)
        } else {
            try container.encodeNil(forKey: .overdueFromDate)
        }
        try container.encode(max(0, Int((plannedDuration / 60).rounded())), forKey: .plannedDuration)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encode(location, forKey: .location)
        try container.encode(reminder, forKey: .reminder)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(subtasks, forKey: .subtasks)
        try container.encode(assigneeId, forKey: .assigneeId)
        try container.encode(recurrenceFrequency, forKey: .recurrenceFrequency)
        try container.encodeIfPresent(recurrenceWeekdays, forKey: .recurrenceWeekdays)
        try container.encode(recurrenceSeriesId, forKey: .recurrenceSeriesId)
        if let completedAt {
            try container.encode(Self.apiDateTimeFormatter.string(from: completedAt), forKey: .completedAt)
        } else {
            try container.encodeNil(forKey: .completedAt)
        }
    }

    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let apiDateTimeFormatter = ISO8601DateFormatter()

    private static func decodeDate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Date? {
        guard let value = try? container.decode(String.self, forKey: key) else {
            return nil
        }
        return apiDateFormatter.date(from: value) ?? apiDateTimeFormatter.date(from: value)
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case dark = "Dark Glass"
    case light = "Crisp Light"
    case highContrast = "High Contrast"

    var id: String { rawValue }
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
