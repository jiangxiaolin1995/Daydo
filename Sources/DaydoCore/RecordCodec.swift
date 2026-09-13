import Foundation
@preconcurrency import CoreData

enum RecordCodec {
    static func records(_ entity: String, in context: NSManagedObjectContext) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.returnsObjectsAsFaults = false
        let rows = try context.fetch(request)
        return Array(Dictionary(rows.compactMap { row -> (String, NSManagedObject)? in
            guard let key = row.value(forKey: "stableID") as? String else { return nil }
            return (key, row)
        }, uniquingKeysWith: newest).values)
    }
    static func newest(_ a: NSManagedObject, _ b: NSManagedObject) -> NSManagedObject {
        let ad = a.value(forKey: "modifiedAt") as? Date ?? .distantPast
        let bd = b.value(forKey: "modifiedAt") as? Date ?? .distantPast
        if ad == bd {
            return (a.value(forKey: "revision") as? String ?? "") > (b.value(forKey: "revision") as? String ?? "") ? a : b
        }
        return ad > bd ? a : b
    }
    static func record(_ entity: String, id: String, in context: NSManagedObjectContext, create: Bool = false) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "stableID == %@", id)
        let matches = try context.fetch(request)
        if let first = matches.first { return matches.dropFirst().reduce(first, newest) }
        if create {
            let row = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
            row.setValue(id, forKey: "stableID")
            return row
        }
        return nil
    }
    static func write(_ list: TodoList, in context: NSManagedObjectContext) throws {
        let row = try record("DDList", id: list.id.uuidString, in: context, create: true)!
        set(row, ["name": list.name, "color": list.color, "sortOrder": list.order,
                  "isArchived": list.isArchived, "revision": list.revision.uuidString, "modifiedAt": list.modifiedAt])
    }
    static func list(_ row: NSManagedObject) -> TodoList? {
        guard let id = uuid(row, "stableID") else { return nil }
        var result = TodoList(id: id, name: text(row, "name"), color: text(row, "color", "#2563EB"),
                              order: row.value(forKey: "sortOrder") as? Double ?? 0)
        result.isArchived = row.value(forKey: "isArchived") as? Bool ?? false
        result.revision = uuid(row, "revision") ?? id
        result.modifiedAt = row.value(forKey: "modifiedAt") as? Date ?? .distantPast
        return result
    }
    static func write(_ task: TodoTask, in context: NSManagedObjectContext) throws {
        let row = try record("DDTask", id: task.id.uuidString, in: context, create: true)!
        let fields = task.fields
        set(row, [
            "title": fields.title, "notes": fields.notes, "listID": fields.listID?.uuidString,
            "day": fields.day?.rawValue, "startMinute": fields.startMinute, "durationMinutes": fields.durationMinutes,
            "timeZoneID": fields.timeZoneID, "priority": fields.priority.rawValue,
            "repeatKind": fields.repeatRule.kind.rawValue,
            "repeatWeekdays": fields.repeatRule.weekdays.map(String.init).joined(separator: ","),
            "repeatUntil": fields.repeatRule.until?.rawValue, "reminderLead": fields.reminderMinutesBefore,
            "reminderMinute": fields.allDayReminderMinute, "completedAt": task.completedAt,
            "deletedFlag": task.isDeleted, "createdAt": task.createdAt, "modifiedAt": task.modifiedAt,
            "revision": task.revision.uuidString, "source": task.source
        ])
    }
    static func task(_ row: NSManagedObject) -> TodoTask? {
        guard let id = uuid(row, "stableID") else { return nil }
        let fields = TaskFields(
            title: text(row, "title"), notes: text(row, "notes"), listID: uuid(row, "listID"),
            day: localDay(row, "day"), startMinute: number(row, "startMinute"),
            durationMinutes: number(row, "durationMinutes") ?? 30,
            timeZoneID: text(row, "timeZoneID", TimeZone.current.identifier),
            priority: Priority(rawValue: number(row, "priority") ?? 0) ?? .none,
            repeatRule: RepeatRule(kind: RepeatKind(rawValue: text(row, "repeatKind")) ?? .never,
                                   weekdays: text(row, "repeatWeekdays").split(separator: ",").compactMap { Int($0) },
                                   until: localDay(row, "repeatUntil")),
            reminderMinutesBefore: number(row, "reminderLead"), allDayReminderMinute: number(row, "reminderMinute") ?? 540)
        var task = TodoTask(id: id, fields: fields, source: text(row, "source", "app"))
        task.completedAt = row.value(forKey: "completedAt") as? Date
        task.isDeleted = row.value(forKey: "deletedFlag") as? Bool ?? false
        task.createdAt = row.value(forKey: "createdAt") as? Date ?? .distantPast
        task.modifiedAt = row.value(forKey: "modifiedAt") as? Date ?? task.createdAt
        task.revision = uuid(row, "revision") ?? id
        return task
    }
    static func write(_ change: OccurrenceOverride, in context: NSManagedObjectContext) throws {
        let row = try record("DDOccurrence", id: change.id, in: context, create: true)!
        let data = try change.fields.map { try JSONEncoder().encode($0) }
        set(row, ["taskID": change.taskID.uuidString, "originalDay": change.originalDay.rawValue,
                  "fields": data, "completedAt": change.completedAt, "deletedFlag": change.isDeleted,
                  "modifiedAt": change.modifiedAt, "revision": change.revision.uuidString, "source": change.source])
    }
    static func occurrence(_ row: NSManagedObject) throws -> OccurrenceOverride? {
        guard let id = uuid(row, "taskID"), let day = localDay(row, "originalDay") else { return nil }
        var result = OccurrenceOverride(taskID: id, originalDay: day)
        if let data = row.value(forKey: "fields") as? Data { result.fields = try JSONDecoder().decode(TaskFields.self, from: data) }
        result.completedAt = row.value(forKey: "completedAt") as? Date
        result.isDeleted = row.value(forKey: "deletedFlag") as? Bool ?? false
        result.modifiedAt = row.value(forKey: "modifiedAt") as? Date ?? .distantPast
        result.revision = uuid(row, "revision") ?? id
        result.source = text(row, "source", "app")
        return result
    }
    static func set(_ row: NSManagedObject, _ values: [String: Any?]) {
        for (key, value) in values { row.setValue(value, forKey: key) }
    }
    static func text(_ row: NSManagedObject, _ key: String, _ fallback: String = "") -> String {
        row.value(forKey: key) as? String ?? fallback
    }
    static func uuid(_ row: NSManagedObject, _ key: String) -> UUID? { UUID(uuidString: text(row, key)) }
    static func number(_ row: NSManagedObject, _ key: String) -> Int? { (row.value(forKey: key) as? NSNumber)?.intValue }
    static func localDay(_ row: NSManagedObject, _ key: String) -> LocalDay? { LocalDay(rawValue: text(row, key)) }
}
