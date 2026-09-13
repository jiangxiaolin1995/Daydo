import Foundation
import CoreFoundation

public struct AgentCommands: Sendable {
    public let repository: TaskRepository
    public init(repository: TaskRepository) { self.repository = repository }
    public func handle(_ name: String, arguments: Data, source: String = "mcp") throws -> Data {
        try repository.authorization.requireAuthorization()
        guard arguments.count <= 1_000_000,
              let object = try JSONSerialization.jsonObject(with: arguments) as? [String: Any] else {
            throw DaydoError.invalid("参数必须是 JSON 对象，最多 1 MB。")
        }
        let input = CommandInput(values: object)
        switch name {
        case "list_lists":
            try input.keys(["includeArchived"])
            let archived = try input.bool("includeArchived") ?? false
            return try encode(repository.snapshot().lists.filter { archived || !$0.isArchived })
        case "create_list":
            try input.keys(["name", "color", "requestId"])
            return try encode(repository.createList(name: input.requiredString("name"),
                                                      color: input.string("color") ?? "#2563EB", requestID: input.string("requestId")))
        case "update_list":
            try input.keys(["listId", "expectedRevision", "name", "color", "order", "isArchived"])
            let id = try input.uuid("listId")
            guard var list = try repository.snapshot().lists.first(where: { $0.id == id }) else { throw DaydoError.notFound("清单") }
            if let name = try input.string("name") { list.name = name }
            if let color = try input.string("color") { list.color = color }
            if let order = try input.number("order") { list.order = order }
            if let archived = try input.bool("isArchived") { list.isArchived = archived }
            return try encode(repository.updateList(list, expectedRevision: input.uuid("expectedRevision")))
        case "create_task":
            try input.keys(["fields", "requestId"])
            let fields = try input.fields(base: TaskFields(title: ""))
            return try encode(repository.createTask(fields: fields, requestID: input.string("requestId"), source: source))
        case "update_task":
            try input.keys(["taskId", "expectedRevision", "fields", "occurrenceDay", "scope"])
            let id = try input.uuid("taskId")
            let snapshot = try repository.snapshot()
            guard let task = snapshot.tasks.first(where: { $0.id == id && !$0.isDeleted }) else { throw DaydoError.notFound("任务") }
            let original = try input.day("occurrenceDay")
            var base = snapshot.overrides.first { $0.taskID == id && $0.originalDay == original }?.fields ?? task.fields
            if let original, base == task.fields { base.day = original }
            let fields = try input.fields(base: base)
            let rawScope = try input.string("scope") ?? "task"
            guard let scope = EditScope(rawValue: rawScope) else { throw DaydoError.invalid("scope 必须是 task、occurrence 或 future。") }
            return try encode(repository.updateTask(id: id, fields: fields, expectedRevision: input.uuid("expectedRevision"),
                                                     originalDay: original, scope: scope, source: source))
        case "set_task_completion":
            try input.keys(["taskId", "occurrenceDay", "completed"])
            let id = try input.uuid("taskId"), original = try input.day("occurrenceDay")
            guard let completed = try input.bool("completed") else { throw DaydoError.invalid("completed 必须明确为 true 或 false。") }
            try repository.setCompletion(id: id, completed: completed, originalDay: original, source: source)
            return try encode(CompletionResult(taskId: id, occurrenceDay: original, completed: completed))
        case "get_task":
            try input.keys(["taskId", "occurrenceDay"])
            let id = try input.uuid("taskId"), original = try input.day("occurrenceDay")
            let snapshot = try repository.snapshot()
            guard let task = snapshot.tasks.first(where: { $0.id == id && !$0.isDeleted }) else { throw DaydoError.notFound("任务") }
            if let original, !OccurrenceEngine.occurs(task, on: original) { throw DaydoError.invalid("无效的 occurrenceDay。") }
            return try encode(TaskResult(task: task, occurrence: snapshot.overrides.first { $0.taskID == id && $0.originalDay == original }))
        case "list_tasks":
            try input.keys(["from", "through", "listId", "completed", "query", "includeUndated", "limit", "offset"])
            let from = try input.day("from") ?? .today(), through = try input.day("through") ?? from
            guard from <= through, through.date(timeZone: TimeZone(secondsFromGMT: 0)!).timeIntervalSince(from.date(timeZone: TimeZone(secondsFromGMT: 0)!)) <= 366 * 86400 else {
                throw DaydoError.invalid("查询范围须按时间升序，且不能超过 366 天。")
            }
            let limit = try input.integer("limit") ?? 100, offset = try input.integer("offset") ?? 0
            guard (1...200).contains(limit), offset >= 0 else { throw DaydoError.invalid("limit 为 1–200，offset 不能小于 0。") }
            let listID = input.values["listId"] == nil ? nil : try input.uuid("listId")
            let completed = try input.bool("completed"), query = try input.string("query")
            var items = OccurrenceEngine.expand(try repository.snapshot(), from: from, through: through,
                                               includeUndated: try input.bool("includeUndated") ?? false)
            items = items.filter {
                (listID == nil || $0.fields.listID == listID) && (completed == nil || $0.isCompleted == completed) &&
                (query == nil || $0.fields.title.localizedCaseInsensitiveContains(query!) || $0.fields.notes.localizedCaseInsensitiveContains(query!))
            }
            return try encode(Page(items: Array(items.dropFirst(offset).prefix(limit)), total: items.count,
                                   nextOffset: offset < items.count && items.count - offset > limit ? offset + limit : nil,
                                   timeZoneID: TimeZone.current.identifier))
        default: throw DaydoError.invalid("未知工具：\(name)")
        }
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

private struct CompletionResult: Encodable { var taskId: UUID; var occurrenceDay: LocalDay?; var completed: Bool }
private struct TaskResult: Encodable { var task: TodoTask; var occurrence: OccurrenceOverride? }
private struct Page: Encodable { var items: [TaskOccurrence]; var total: Int; var nextOffset: Int?; var timeZoneID: String }
private struct CommandInput {
    var values: [String: Any]
    func keys(_ allowed: Set<String>) throws {
        let unknown = Set(values.keys).subtracting(allowed)
        guard unknown.isEmpty else { throw DaydoError.invalid("未知参数：\(unknown.sorted().joined(separator: ", "))") }
    }
    func string(_ key: String) throws -> String? {
        guard let value = values[key] else { return nil }
        guard let string = value as? String else { throw DaydoError.invalid("\(key) 必须为字符串。") }
        return string
    }
    func requiredString(_ key: String) throws -> String {
        guard let value = try string(key) else { throw DaydoError.invalid("缺少 \(key)。") }; return value
    }
    func uuid(_ key: String) throws -> UUID {
        guard let id = UUID(uuidString: try requiredString(key)) else { throw DaydoError.invalid("\(key) 必须是 UUID。") }; return id
    }
    func day(_ key: String) throws -> LocalDay? {
        guard let value = try string(key) else { return nil }
        guard let day = LocalDay(rawValue: value) else { throw DaydoError.invalid("\(key) 必须为真实的 YYYY-MM-DD 日期。") }; return day
    }
    func bool(_ key: String) throws -> Bool? {
        guard let value = values[key] else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw DaydoError.invalid("\(key) 必须为布尔值。")
        }
        return number.boolValue
    }
    func number(_ key: String) throws -> Double? {
        guard let value = values[key] else { return nil }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
            throw DaydoError.invalid("\(key) 必须为有限数值。")
        }
        return number.doubleValue
    }
    func integer(_ key: String) throws -> Int? {
        guard let value = try number(key) else { return nil }
        guard value.rounded() == value, value >= 0, value <= Double(Int32.max) else { throw DaydoError.invalid("\(key) 必须为有效整数。") }
        return Int(value)
    }
    func fields(base: TaskFields) throws -> TaskFields {
        guard let patch = values["fields"] as? [String: Any], !patch.isEmpty else { throw DaydoError.invalid("fields 必须是非空对象。") }
        let allowed: Set<String> = ["title", "notes", "listID", "day", "startMinute", "durationMinutes", "timeZoneID", "priority", "repeatRule", "reminderMinutesBefore", "allDayReminderMinute"]
        try CommandInput(values: patch).keys(allowed)
        var merged = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
        for (key, value) in patch { merged[key] = value }
        if var rule = patch["repeatRule"] as? [String: Any] {
            try CommandInput(values: rule).keys(["kind", "weekdays", "until"])
            if rule["weekdays"] == nil { rule["weekdays"] = [] }
            merged["repeatRule"] = rule
        }
        do { return try JSONDecoder().decode(TaskFields.self, from: JSONSerialization.data(withJSONObject: merged)).validated() }
        catch let error as DaydoError { throw error }
        catch { throw DaydoError.invalid("任务字段类型或日期格式无效：\(error.localizedDescription)") }
    }
}
