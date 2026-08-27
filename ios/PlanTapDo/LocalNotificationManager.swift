import Foundation
import UserNotifications
import SwiftUI

final class LocalNotificationManager {
    static let shared = LocalNotificationManager()
    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "plantapdo.task."

    func synchronize(todos: [TodoEntry], categories: [Category]) {
        let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        let candidates = todos.compactMap { todo -> (TodoEntry, NotificationPreference, Date)? in
            guard todo.status == .pending || todo.status == .inProgress,
                  let eventDate = eventDate(for: todo) else { return nil }
            let preference = todo.notificationPreference
                ?? todo.categoryId.flatMap { categoryByID[$0]?.notificationPreference }
                ?? .none
            guard preference != .none else { return nil }
            return (todo, preference, eventDate)
        }
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            self.center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(self.identifierPrefix) })
            guard !candidates.isEmpty else { return }
            self.center.requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
                guard granted else { return }
                self?.schedule(candidates)
            }
        }
    }

    func removeNotifications(for todoID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers(for: todoID))
    }

    private func schedule(_ candidates: [(TodoEntry, NotificationPreference, Date)]) {
        let now = Date()
        for (todo, preference, eventDate) in candidates {
            if let minutes = preference.leadMinutes {
                addRequest(todo: todo, kind: "before", date: eventDate.addingTimeInterval(TimeInterval(-minutes * 60)), now: now, body: "Starts in \(minutes) minutes.")
            }
            if preference.includesAtTime {
                addRequest(todo: todo, kind: "atTime", date: eventDate, now: now, body: "It’s time to start this task.")
            }
        }
    }

    private func addRequest(todo: TodoEntry, kind: String, date: Date, now: Date, body: String) {
        guard date > now else { return }
        let content = UNMutableNotificationContent()
        content.title = todo.title
        content.body = body
        content.sound = .default
        content.userInfo = ["todoID": todo.id.uuidString]
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
        center.add(UNNotificationRequest(identifier: identifier(for: todo.id, kind: kind), content: content, trigger: trigger))
    }

    private func eventDate(for todo: TodoEntry) -> Date? {
        let time = todo.plannedStartTime ?? todo.dueTime
        let day = todo.plannedStartTime == nil ? (todo.dueDate ?? todo.doDate) : todo.doDate
        guard let time, let parsed = Self.timeComponents(time) else { return nil }
        return Calendar.autoupdatingCurrent.date(bySettingHour: parsed.hour, minute: parsed.minute, second: 0, of: day)
    }

    private static func timeComponents(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return (parts[0], parts[1])
    }

    private func identifiers(for todo: TodoEntry) -> [String] { identifiers(for: todo.id) }
    private func identifiers(for todoID: UUID) -> [String] { [identifier(for: todoID, kind: "before"), identifier(for: todoID, kind: "atTime")] }
    private func identifier(for todoID: UUID, kind: String) -> String { "\(identifierPrefix)\(todoID.uuidString).\(kind)" }
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
