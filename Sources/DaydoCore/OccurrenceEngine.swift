import Foundation

public enum OccurrenceEngine {
    public static func occurs(_ task: TodoTask, on day: LocalDay) -> Bool {
        guard !task.isDeleted, let start = task.fields.day, day >= start else { return false }
        let rule = task.fields.repeatRule
        if let end = rule.until, day > end { return false }
        switch rule.kind {
        case .never: return day == start
        case .daily: return true
        case .weekdays: return (2...6).contains(day.weekday)
        case .weekly: return rule.weekdays.contains(day.weekday)
        }
    }
    public static func expand(_ snapshot: TaskSnapshot, from: LocalDay, through: LocalDay,
                              includeUndated: Bool = false, includeArchived: Bool = false) -> [TaskOccurrence] {
        guard from <= through else { return [] }
        let archived = Set(snapshot.lists.filter(\.isArchived).map(\.id))
        var result: [TaskOccurrence] = []
        for task in snapshot.tasks where !task.isDeleted {
            if !includeArchived, let listID = task.fields.listID, archived.contains(listID) { continue }
            if task.fields.repeatRule.kind == .never {
                if let day = task.fields.day {
                    guard day >= from && day <= through else { continue }
                } else if !includeUndated { continue }
                result.append(TaskOccurrence(taskID: task.id, originalDay: nil, fields: task.fields,
                                             completedAt: task.completedAt, revision: task.revision, source: task.source))
                continue
            }
            let changes = Dictionary(snapshot.overrides.filter { $0.taskID == task.id }.map { ($0.originalDay, $0) },
                                     uniquingKeysWith: { $0.modifiedAt > $1.modifiedAt ? $0 : $1 })
            var current = max(from, task.fields.day ?? from)
            let end = min(through, task.fields.repeatRule.until ?? through)
            while current <= end {
                if occurs(task, on: current), changes[current] == nil {
                    var fields = task.fields
                    fields.day = current
                    result.append(TaskOccurrence(taskID: task.id, originalDay: current, fields: fields,
                                                 completedAt: nil, revision: task.revision, source: task.source))
                }
                if current == end { break }
                current = current.adding(days: 1)
            }
            for change in changes.values where !change.isDeleted && occurs(task, on: change.originalDay) {
                var fields = change.fields ?? task.fields
                if change.fields == nil { fields.day = change.originalDay }
                guard let actualDay = fields.day, actualDay >= from, actualDay <= through else { continue }
                if !includeArchived, let listID = fields.listID, archived.contains(listID) { continue }
                result.append(TaskOccurrence(taskID: task.id, originalDay: change.originalDay, fields: fields,
                                             completedAt: change.completedAt, revision: change.revision, source: change.source))
            }
        }
        return result.sorted(by: order)
    }

    public static func order(_ lhs: TaskOccurrence, _ rhs: TaskOccurrence) -> Bool {
        if lhs.fields.day != rhs.fields.day {
            return (lhs.fields.day?.rawValue ?? "") < (rhs.fields.day?.rawValue ?? "")
        }
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        if lhs.fields.startMinute != rhs.fields.startMinute {
            return (lhs.fields.startMinute ?? 1441) < (rhs.fields.startMinute ?? 1441)
        }
        if lhs.fields.priority != rhs.fields.priority { return lhs.fields.priority.rawValue > rhs.fields.priority.rawValue }
        return lhs.id < rhs.id
    }
}
