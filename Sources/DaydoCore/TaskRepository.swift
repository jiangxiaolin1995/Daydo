import Foundation
import CryptoKit
@preconcurrency import CoreData

public final class TaskRepository: @unchecked Sendable {
    let store: PersistentStore
    let authorization: any AuthorizationChecking
    public var persistentStoreCoordinator: NSPersistentStoreCoordinator { store.container.persistentStoreCoordinator }
    @discardableResult public func consumeHistory(consumer: String) throws -> Int {
        try store.consumeHistory(authorization: authorization, consumer: consumer)
    }
    public func close() throws { try store.close() }

    public init(storeURL: URL, authorization: any AuthorizationChecking, cloudContainerID: String? = nil) throws {
        self.authorization = authorization
        store = try PersistentStore(url: storeURL, cloudContainerID: cloudContainerID)
    }
    public func snapshot() throws -> TaskSnapshot {
        try store.access(authorization: authorization, write: false) { context in try Self.snapshot(in: context) }
    }
    static func snapshot(in context: NSManagedObjectContext) throws -> TaskSnapshot {
        try TaskSnapshot(
            lists: RecordCodec.records("DDList", in: context).compactMap(RecordCodec.list).sorted { $0.order < $1.order },
            tasks: RecordCodec.records("DDTask", in: context).compactMap(RecordCodec.task),
            overrides: RecordCodec.records("DDOccurrence", in: context).compactMap { try RecordCodec.occurrence($0) })
    }
    public func createList(name: String, color: String = "#2563EB", requestID: String? = nil) throws -> TodoList {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.validateList(name: name, color: color)
        return try store.access(authorization: authorization, write: true) { context in
            let fingerprint = Self.hash(name + "\n" + color)
            if let resultID = try Self.receipt("create_list", requestID, fingerprint, in: context),
               let row = try RecordCodec.record("DDList", id: resultID, in: context),
               let list = RecordCodec.list(row) { return list }
            let existing = try RecordCodec.records("DDList", in: context).compactMap(RecordCodec.list)
            let list = TodoList(name: name, color: color, order: (existing.map(\.order).max() ?? -1) + 1)
            try RecordCodec.write(list, in: context)
            try Self.saveReceipt("create_list", requestID, fingerprint, resultID: list.id.uuidString, in: context)
            return list
        }
    }
    public func updateList(_ list: TodoList, expectedRevision: UUID) throws -> TodoList {
        try Self.validateList(name: list.name, color: list.color)
        return try store.access(authorization: authorization, write: true) { context in
            guard let row = try RecordCodec.record("DDList", id: list.id.uuidString, in: context),
                  let current = RecordCodec.list(row) else { throw DaydoError.notFound("清单") }
            guard current.revision == expectedRevision else { throw DaydoError.conflict }
            var updated = list
            updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.revision = UUID(); updated.modifiedAt = Date()
            try RecordCodec.write(updated, in: context)
            return updated
        }
    }
    public func createTask(fields: TaskFields, requestID: String? = nil, source: String = "app") throws -> TodoTask {
        let fields = try fields.validated()
        return try store.access(authorization: authorization, write: true) { context in
            try Self.validateListReference(fields.listID, in: context)
            let fingerprint = try Self.fingerprint(fields)
            if let resultID = try Self.receipt("create_task", requestID, fingerprint, in: context),
               let row = try RecordCodec.record("DDTask", id: resultID, in: context),
               let task = RecordCodec.task(row) { return task }
            let task = TodoTask(fields: fields, source: source)
            try RecordCodec.write(task, in: context)
            try Self.saveReceipt("create_task", requestID, fingerprint, resultID: task.id.uuidString, in: context)
            return task
        }
    }
    public func updateTask(id: UUID, fields: TaskFields, expectedRevision: UUID, originalDay: LocalDay? = nil,
                           scope: EditScope = .task, source: String = "app") throws -> TodoTask {
        let fields = try fields.validated()
        return try store.access(authorization: authorization, write: true) { context in
            var task = try Self.task(id, in: context)
            guard !task.isDeleted else { throw DaydoError.notFound("任务") }
            try Self.validateListReference(fields.listID, in: context)
            if task.fields.repeatRule.kind == .never {
                guard task.revision == expectedRevision else { throw DaydoError.conflict }
                task.fields = fields; task.modifiedAt = Date(); task.revision = UUID(); task.source = source
                if fields.repeatRule.kind != .never { task.completedAt = nil }
                try RecordCodec.write(task, in: context)
                return task
            }
            guard let originalDay, scope != .task, OccurrenceEngine.occurs(task, on: originalDay) else {
                throw DaydoError.invalid("编辑重复任务必须指定 occurrenceDay，以及 occurrence 或 future 范围。")
            }
            var change = try Self.change(id, day: originalDay, in: context)
            guard (change?.revision ?? task.revision) == expectedRevision else { throw DaydoError.conflict }
            if scope == .occurrence {
                guard fields.day != nil else { throw DaydoError.invalid("重复实例需要计划日期。") }
                if change == nil { change = OccurrenceOverride(taskID: id, originalDay: originalDay) }
                change!.fields = fields; change!.modifiedAt = Date(); change!.revision = UUID(); change!.source = source
                try RecordCodec.write(change!, in: context)
                var response = task
                response.fields = fields; response.revision = change!.revision
                response.completedAt = change!.completedAt; response.source = source
                return response
            }
            var future = TodoTask(fields: fields, source: source)
            future.createdAt = task.createdAt
            if task.fields.day == originalDay { task.isDeleted = true }
            else { task.fields.repeatRule.until = originalDay.adding(days: -1) }
            task.modifiedAt = Date(); task.revision = UUID(); task.source = source
            try RecordCodec.write(task, in: context)
            try RecordCodec.write(future, in: context)
            let zone = TimeZone(secondsFromGMT: 0)!
            let offset = Int((fields.day ?? originalDay).date(timeZone: zone)
                .timeIntervalSince(originalDay.date(timeZone: zone)) / 86400)
            for row in try RecordCodec.records("DDOccurrence", in: context) {
                guard var existing = try RecordCodec.occurrence(row), existing.taskID == id,
                      existing.originalDay >= originalDay else { continue }
                existing.taskID = future.id
                existing.originalDay = existing.originalDay.adding(days: offset)
                if let actualDay = existing.fields?.day { existing.fields?.day = actualDay.adding(days: offset) }
                existing.modifiedAt = Date(); existing.revision = UUID()
                try RecordCodec.write(existing, in: context)
            }
            return future
        }
    }
    public func setCompletion(id: UUID, completed: Bool, originalDay: LocalDay? = nil, source: String = "app") throws {
        try store.access(authorization: authorization, write: true) { context in
            var task = try Self.task(id, in: context)
            guard !task.isDeleted else { throw DaydoError.notFound("任务") }
            if task.fields.repeatRule.kind == .never {
                guard originalDay == nil else { throw DaydoError.invalid("单次任务不接受 occurrenceDay。") }
                guard (task.completedAt != nil) != completed else { return }
                task.completedAt = completed ? Date() : nil
                task.modifiedAt = Date(); task.revision = UUID(); task.source = source
                try RecordCodec.write(task, in: context)
            } else {
                guard let originalDay, OccurrenceEngine.occurs(task, on: originalDay) else {
                    throw DaydoError.invalid("完成重复任务需要有效的 occurrenceDay。")
                }
                var change = try Self.change(id, day: originalDay, in: context) ?? OccurrenceOverride(taskID: id, originalDay: originalDay)
                guard !change.isDeleted else { throw DaydoError.notFound("任务实例") }
                guard (change.completedAt != nil) != completed else { return }
                change.completedAt = completed ? Date() : nil
                change.modifiedAt = Date(); change.revision = UUID(); change.source = source
                try RecordCodec.write(change, in: context)
            }
        }
    }
    public func setDeleted(id: UUID, deleted: Bool, originalDay: LocalDay? = nil, source: String = "app") throws {
        try store.access(authorization: authorization, write: true) { context in
            var task = try Self.task(id, in: context)
            if task.fields.repeatRule.kind == .never || originalDay == nil {
                task.isDeleted = deleted; task.modifiedAt = Date(); task.revision = UUID(); task.source = source
                try RecordCodec.write(task, in: context)
            } else if let originalDay {
                guard OccurrenceEngine.occurs(task, on: originalDay) else { throw DaydoError.invalid("无效的重复实例。") }
                var change = try Self.change(id, day: originalDay, in: context) ?? OccurrenceOverride(taskID: id, originalDay: originalDay)
                change.isDeleted = deleted; change.modifiedAt = Date(); change.revision = UUID(); change.source = source
                try RecordCodec.write(change, in: context)
            }
        }
    }
    static func task(_ id: UUID, in context: NSManagedObjectContext) throws -> TodoTask {
        guard let row = try RecordCodec.record("DDTask", id: id.uuidString, in: context),
              let task = RecordCodec.task(row) else { throw DaydoError.notFound("任务") }
        return task
    }
    static func change(_ id: UUID, day: LocalDay, in context: NSManagedObjectContext) throws -> OccurrenceOverride? {
        let key = OccurrenceOverride(taskID: id, originalDay: day).id
        guard let row = try RecordCodec.record("DDOccurrence", id: key, in: context) else { return nil }
        return try RecordCodec.occurrence(row)
    }
    static func validateList(name: String, color: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { throw DaydoError.invalid("清单名称为 1–80 个字符。") }
        guard color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { throw DaydoError.invalid("清单颜色需为 #RRGGBB。") }
    }
    static func validateListReference(_ id: UUID?, in context: NSManagedObjectContext) throws {
        if let id {
            guard let row = try RecordCodec.record("DDList", id: id.uuidString, in: context),
                  let list = RecordCodec.list(row), !list.isArchived else { throw DaydoError.invalid("请选择一个有效的未归档清单。") }
        }
    }
    static func hash(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    static func fingerprint<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }
    static func receipt(_ action: String, _ requestID: String?, _ fingerprint: String, in context: NSManagedObjectContext) throws -> String? {
        guard let requestID else { return nil }
        guard !requestID.isEmpty, requestID.count <= 200 else { throw DaydoError.invalid("requestId 需为 1–200 个字符。") }
        guard let row = try RecordCodec.record("DDReceipt", id: hash(action + ":" + requestID), in: context) else { return nil }
        guard RecordCodec.text(row, "fingerprint") == fingerprint else { throw DaydoError.invalid("相同 requestId 不能用于不同内容。") }
        return RecordCodec.text(row, "resultID")
    }
    static func saveReceipt(_ action: String, _ requestID: String?, _ fingerprint: String, resultID: String, in context: NSManagedObjectContext) throws {
        guard let requestID else { return }
        let row = try RecordCodec.record("DDReceipt", id: hash(action + ":" + requestID), in: context, create: true)!
        RecordCodec.set(row, ["fingerprint": fingerprint, "resultID": resultID, "modifiedAt": Date(), "revision": UUID().uuidString])
    }
}
