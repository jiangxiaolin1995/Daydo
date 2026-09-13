import Foundation
import UserNotifications
import DaydoCore

actor NotificationService {
    private let center = UNUserNotificationCenter.current()
    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    func status() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
    func reconcile(_ snapshot: TaskSnapshot, namespace: String, enabled: Bool) async throws {
        let gate = StoreAccessGate(namespace: namespace)
        try gate.requireAuthorization()
        guard enabled, await status() == .authorized else {
            center.removeAllPendingNotificationRequests()
            return
        }
        let planned = ReminderPlanner.plan(snapshot)
        let pending = await center.pendingNotificationRequests()
        try gate.requireAuthorization()
        let prefix = "daydo." + namespace + "."
        let wanted = Set(planned.map { prefix + $0.id })
        let obsolete = pending.filter { !wanted.contains($0.identifier) }.map(\.identifier)
        if !obsolete.isEmpty { center.removePendingNotificationRequests(withIdentifiers: obsolete) }
        for reminder in planned {
            try gate.requireAuthorization()
            let id = prefix + reminder.id
            if let existing = pending.first(where: { $0.identifier == id }),
               existing.content.title == reminder.title,
               let next = (existing.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
               abs(next.timeIntervalSince(reminder.fireDate)) < 1 { continue }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = "到了安排好的时间。"
            content.sound = .default
            content.userInfo = ["url": "daydo://task/\(reminder.id)"]
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            components.timeZone = calendar.timeZone
            let request = UNNotificationRequest(identifier: id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try await center.add(request)
            do { try gate.requireAuthorization() }
            catch {
                center.removePendingNotificationRequests(withIdentifiers: [id])
                throw error
            }
        }
    }
}
