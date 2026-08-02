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

struct TeamMember: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var role: String
    var department: String
    var status: String
    var capacityMinutes: Int
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
    let id: UUID
    var title: String
    var isCompleted: Bool
}

enum PriorityLevel: String, Codable, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case urgent = "Urgent"

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
    case cancelled
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
    var assigneeId: UUID?
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
