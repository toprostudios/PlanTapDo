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
    let start: Date
    let end: Date?
    let duration: TimeInterval? // seconds
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

struct TodoEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var description: String?
    var doDate: Date             // Date scheduled to do it
    var dueDate: Date?           // Deadline date
    var dueTime: String?         // HH:MM (e.g. "18:00")
    var descriptiveDeadline: String? // Descriptive deadline note (no effect on calendar position)
    var plannedStartTime: String? // HH:MM (e.g. "09:30")
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

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case doDate
        case dueDate
        case dueTime
        case descriptiveDeadline
        case plannedStartTime
        case plannedDuration
        case categoryId
        case status
        case priority
        case location
        case reminder
        case labels
        case subtasks
        case assigneeId
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
        assigneeId: String?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.doDate = doDate
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.descriptiveDeadline = descriptiveDeadline
        self.plannedStartTime = plannedStartTime
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
        try container.encode(max(0, Int((plannedDuration / 60).rounded())), forKey: .plannedDuration)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encode(location, forKey: .location)
        try container.encode(reminder, forKey: .reminder)
        try container.encodeIfPresent(labels, forKey: .labels)
        try container.encodeIfPresent(subtasks, forKey: .subtasks)
        try container.encode(assigneeId, forKey: .assigneeId)
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
