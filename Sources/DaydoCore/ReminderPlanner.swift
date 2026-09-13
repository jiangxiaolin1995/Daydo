import Foundation

public struct PlannedReminder: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var fireDate: Date
    public var taskID: UUID
    public var originalDay: LocalDay?
}

public enum ReminderPlanner {
    public static func plan(_ snapshot: TaskSnapshot, now: Date = Date(), limit: Int = 48) -> [PlannedReminder] {
        let today = LocalDay(now)
        let occurrences = OccurrenceEngine.expand(snapshot, from: today.adding(days: -2), through: today.adding(days: 38))
        let reminders = occurrences.compactMap { occurrence -> PlannedReminder? in
            guard !occurrence.isCompleted, let lead = occurrence.fields.reminderMinutesBefore,
                  let day = occurrence.fields.day, let zone = TimeZone(identifier: occurrence.fields.timeZoneID) else { return nil }
            let minute = occurrence.fields.startMinute ?? occurrence.fields.allDayReminderMinute
            let fireDate = day.date(timeZone: zone, minute: minute).addingTimeInterval(-Double(lead) * 60)
            guard fireDate > now, fireDate < now.addingTimeInterval(31 * 86400) else { return nil }
            return PlannedReminder(id: occurrence.id, title: occurrence.fields.title, fireDate: fireDate,
                                   taskID: occurrence.taskID, originalDay: occurrence.originalDay)
        }.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
        return Array(reminders.prefix(max(0, limit)))
    }
}
