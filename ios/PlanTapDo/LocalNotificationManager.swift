import Foundation
import UserNotifications
import SwiftUI

final class LocalNotificationManager {
    static let shared = LocalNotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "plantapdo.task."
    private let generationLock = NSLock()
    private var latestGeneration = 0

    func synchronize(todos: [TodoEntry], categories: [Category]) {
        let generation = nextGeneration()
        let candidates = NotificationSchedulePlanner.plan(
            todos: todos,
            categories: categories,
            now: Date()
        )
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            guard self.performIfCurrent(generation, action: {
                self.center.removePendingNotificationRequests(
                    withIdentifiers: requests.map(\.identifier).filter {
                        $0.hasPrefix(self.identifierPrefix)
                    }
                )
            }) else { return }
            guard !candidates.isEmpty else { return }
            self.center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
                guard granted else { return }
                self?.schedule(candidates, generation: generation)
            }
        }
    }

    func removeNotifications(for todoID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers(for: todoID))
    }

    private func nextGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        latestGeneration &+= 1
        return latestGeneration
    }

    @discardableResult
    private func performIfCurrent(_ generation: Int, action: () -> Void) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        guard generation == latestGeneration else { return false }
        action()
        return true
    }

    private func schedule(
        _ candidates: [NotificationSchedulePlanner.Candidate],
        generation: Int
    ) {
        performIfCurrent(generation) {
            for candidate in candidates {
                addRequest(candidate)
            }
        }
    }

    private func addRequest(_ candidate: NotificationSchedulePlanner.Candidate) {
        let content = UNMutableNotificationContent()
        content.title = candidate.title
        content.body = candidate.body
        content.sound = .default
        content.userInfo = ["todoID": candidate.todoID.uuidString]
        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: candidate.date
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        center.add(
            UNNotificationRequest(
                identifier: identifier(for: candidate.todoID, kind: candidate.kind),
                content: content,
                trigger: trigger
            )
        )
    }

    private func identifiers(for todo: TodoEntry) -> [String] { identifiers(for: todo.id) }
    private func identifiers(for todoID: UUID) -> [String] { [identifier(for: todoID, kind: "before"), identifier(for: todoID, kind: "atTime")] }
    private func identifier(for todoID: UUID, kind: String) -> String { "\(identifierPrefix)\(todoID.uuidString).\(kind)" }
}

enum NotificationSchedulePlanner {
    // iOS retains at most 64 pending local notifications per app. Select the
    // nearest reminders deterministically so later tasks cannot evict earlier
    // ones in an implementation-defined order.
    static let maximumPendingNotifications = 64

    struct Candidate: Equatable {
        let todoID: UUID
        let title: String
        let kind: String
        let date: Date
        let body: String
    }

    static func plan(
        todos: [TodoEntry],
        categories: [Category],
        now: Date
    ) -> [Candidate] {
        let categoryByID = Dictionary(
            categories.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var candidates: [Candidate] = []

        for todo in todos where todo.status == .pending || todo.status == .inProgress {
            guard let eventDate = eventDate(for: todo) else { continue }
            let preference = todo.notificationPreference
                ?? todo.categoryId.flatMap { categoryByID[$0]?.notificationPreference }
                ?? .none
            if let minutes = preference.leadMinutes {
                let date = eventDate.addingTimeInterval(TimeInterval(-minutes * 60))
                if date > now {
                    candidates.append(
                        Candidate(
                            todoID: todo.id,
                            title: todo.title,
                            kind: "before",
                            date: date,
                            body: "Starts in \(minutes) minutes."
                        )
                    )
                }
            }
            if preference.includesAtTime, eventDate > now {
                candidates.append(
                    Candidate(
                        todoID: todo.id,
                        title: todo.title,
                        kind: "atTime",
                        date: eventDate,
                        body: "It’s time to start this task."
                    )
                )
            }
        }

        return Array(
            candidates.sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                if $0.todoID != $1.todoID {
                    return $0.todoID.uuidString < $1.todoID.uuidString
                }
                return $0.kind < $1.kind
            }
            .prefix(maximumPendingNotifications)
        )
    }

    private static func eventDate(for todo: TodoEntry) -> Date? {
        let time = todo.plannedStartTime ?? todo.dueTime
        let day = todo.plannedStartTime == nil ? (todo.dueDate ?? todo.doDate) : todo.doDate
        guard let time, let parsed = timeComponents(time) else { return nil }
        return Calendar.autoupdatingCurrent.date(
            bySettingHour: parsed.hour,
            minute: parsed.minute,
            second: 0,
            of: day
        )
    }

    private static func timeComponents(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2,
              (0...23).contains(parts[0]),
              (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }
}

struct NotificationPreferencePicker: View {
    @Binding var preference: NotificationPreference?
    var inheritedPreference: NotificationPreference?
    var allowsInheritedDefault: Bool

    private let options: [NotificationPreference] = [
        .none, .atTime, .before(minutes: 5), .before(minutes: 10),
        .before(minutes: 15), .before(minutes: 30), .before(minutes: 60),
        .beforeAndAtTime(minutes: 5), .beforeAndAtTime(minutes: 10),
        .beforeAndAtTime(minutes: 15), .beforeAndAtTime(minutes: 30), .beforeAndAtTime(minutes: 60)
    ]

    var body: some View {
        Picker("Notification", selection: $preference) {
            if allowsInheritedDefault {
                Text("Category default (\(inheritedPreference?.label ?? "Off"))").tag(NotificationPreference?.none)
            }
            ForEach(options) { option in
                Text(option.label).tag(Optional(option))
            }
        }
    }
}
