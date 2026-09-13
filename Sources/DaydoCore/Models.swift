import Foundation

public enum Priority: Int, Codable, CaseIterable, Sendable {
    case none = 0, low = 1, medium = 2, high = 3
    public var title: String {
        switch self { case .none: "无优先级"; case .low: "低"; case .medium: "中"; case .high: "高" }
    }
}

public enum RepeatKind: String, Codable, CaseIterable, Sendable {
    case never, daily, weekdays, weekly
    public var title: String {
        switch self { case .never: "不重复"; case .daily: "每天"; case .weekdays: "工作日"; case .weekly: "每周" }
    }
}

public struct RepeatRule: Codable, Equatable, Sendable {
    public var kind: RepeatKind
    /// Gregorian weekdays: Sunday = 1, Monday = 2.
    public var weekdays: [Int]
    public var until: LocalDay?
    public init(kind: RepeatKind = .never, weekdays: [Int] = [], until: LocalDay? = nil) {
        self.kind = kind; self.weekdays = weekdays; self.until = until
    }
}

public struct TodoList: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var color: String
    public var order: Double
    public var isArchived: Bool
    public var revision: UUID
    public var modifiedAt: Date
    public init(id: UUID = UUID(), name: String, color: String = "#2563EB", order: Double = 0) {
        self.id = id; self.name = name; self.color = color; self.order = order
        self.isArchived = false; self.revision = UUID(); self.modifiedAt = Date()
    }
}

public struct TaskFields: Codable, Equatable, Sendable {
    public var title: String
    public var notes: String
    public var listID: UUID?
    public var day: LocalDay?
    public var startMinute: Int?
    public var durationMinutes: Int
    public var timeZoneID: String
    public var priority: Priority
    public var repeatRule: RepeatRule
    public var reminderMinutesBefore: Int?
    public var allDayReminderMinute: Int

    public init(title: String, notes: String = "", listID: UUID? = nil, day: LocalDay? = nil,
                startMinute: Int? = nil, durationMinutes: Int = 30,
                timeZoneID: String = TimeZone.current.identifier, priority: Priority = .none,
                repeatRule: RepeatRule = RepeatRule(), reminderMinutesBefore: Int? = nil,
                allDayReminderMinute: Int = 9 * 60) {
        self.title = title; self.notes = notes; self.listID = listID; self.day = day
        self.startMinute = startMinute; self.durationMinutes = durationMinutes
        self.timeZoneID = timeZoneID; self.priority = priority; self.repeatRule = repeatRule
        self.reminderMinutesBefore = reminderMinutesBefore; self.allDayReminderMinute = allDayReminderMinute
    }

    public func validated() throws -> Self {
        var result = self
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.title.isEmpty, result.title.count <= 500 else {
            throw DaydoError.invalid("标题不能为空，且不能超过 500 个字符。")
        }
        guard notes.count <= 100_000 else { throw DaydoError.invalid("备注过长。") }
        guard TimeZone(identifier: timeZoneID) != nil else { throw DaydoError.invalid("无效的时区。") }
        guard (15...1440).contains(durationMinutes), durationMinutes % 15 == 0 else {
            throw DaydoError.invalid("时长须为 15 分钟的倍数，最多 24 小时。")
        }
        if let startMinute {
            guard day != nil, (0..<1440).contains(startMinute) else {
                throw DaydoError.invalid("开始时间需要有效的计划日期。")
            }
        }
        if repeatRule.kind != .never && day == nil { throw DaydoError.invalid("重复任务需要开始日期。") }
        if repeatRule.kind == .weekly && (repeatRule.weekdays.isEmpty || !repeatRule.weekdays.allSatisfy({ (1...7).contains($0) })) {
            throw DaydoError.invalid("每周重复至少选择一天。")
        }
        if let until = repeatRule.until, let day, until < day { throw DaydoError.invalid("重复结束日期不能早于开始日期。") }
        if let lead = reminderMinutesBefore {
            guard day != nil, (0...10080).contains(lead), (0..<1440).contains(allDayReminderMinute) else {
                throw DaydoError.invalid("提醒需要计划日期和有效的时间。")
            }
        }
        result.repeatRule.weekdays = Array(Set(repeatRule.weekdays)).sorted()
        return result
    }
}

public struct TodoTask: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var fields: TaskFields
    public var completedAt: Date?
    public var isDeleted: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var revision: UUID
    public var source: String
    public init(id: UUID = UUID(), fields: TaskFields, source: String = "app") {
        self.id = id; self.fields = fields; self.source = source
        self.completedAt = nil; self.isDeleted = false
        self.createdAt = Date(); self.modifiedAt = createdAt; self.revision = UUID()
    }
}

public struct OccurrenceOverride: Identifiable, Codable, Equatable, Sendable {
    public var taskID: UUID
    public var originalDay: LocalDay
    public var fields: TaskFields?
    public var completedAt: Date?
    public var isDeleted: Bool = false
    public var modifiedAt: Date = Date()
    public var revision: UUID = UUID()
    public var source: String = "app"
    public var id: String { "\(taskID.uuidString.lowercased())/\(originalDay)" }
    public init(taskID: UUID, originalDay: LocalDay) {
        self.taskID = taskID; self.originalDay = originalDay
    }
}

public struct TaskOccurrence: Identifiable, Codable, Equatable, Sendable {
    public var taskID: UUID
    public var originalDay: LocalDay?
    public var fields: TaskFields
    public var completedAt: Date?
    public var revision: UUID
    public var source: String
    public init(taskID: UUID, originalDay: LocalDay?, fields: TaskFields, completedAt: Date?, revision: UUID, source: String) {
        self.taskID = taskID; self.originalDay = originalDay; self.fields = fields
        self.completedAt = completedAt; self.revision = revision; self.source = source
    }
    public var id: String { "\(taskID.uuidString.lowercased())/\(originalDay?.rawValue ?? "single")" }
    public var isCompleted: Bool { completedAt != nil }
    public var startDate: Date? {
        guard let day = fields.day, let minute = fields.startMinute,
              let zone = TimeZone(identifier: fields.timeZoneID) else { return nil }
        return day.date(timeZone: zone, minute: minute)
    }
}

public struct TaskSnapshot: Codable, Equatable, Sendable {
    public var lists: [TodoList]
    public var tasks: [TodoTask]
    public var overrides: [OccurrenceOverride]
    public init(lists: [TodoList] = [], tasks: [TodoTask] = [], overrides: [OccurrenceOverride] = []) {
        self.lists = lists; self.tasks = tasks; self.overrides = overrides
    }
}

public enum EditScope: String, Codable, Sendable { case occurrence, future, task }
