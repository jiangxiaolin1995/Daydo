import Foundation
@preconcurrency import CoreData

public struct BackupEnvelope: Codable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var snapshot: TaskSnapshot
    public init(snapshot: TaskSnapshot) { schemaVersion = 1; exportedAt = Date(); self.snapshot = snapshot }
}

public struct ImportPreview: Equatable, Sendable {
    public var newLists: Int
    public var newTasks: Int
    public var newOverrides: Int
    public var skipped: Int
    public init(newLists: Int = 0, newTasks: Int = 0, newOverrides: Int = 0, skipped: Int = 0) {
        self.newLists = newLists; self.newTasks = newTasks; self.newOverrides = newOverrides; self.skipped = skipped
    }
}

extension TaskRepository {
    public func exportBackup() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(BackupEnvelope(snapshot: snapshot()))
    }
    public func previewImport(_ data: Data) throws -> ImportPreview {
        try authorization.requireAuthorization()
        let incoming = try Self.decodeBackup(data)
        return Self.importPreview(incoming, current: try snapshot())
    }
    @discardableResult public func importBackup(_ data: Data) throws -> ImportPreview {
        try authorization.requireAuthorization()
        let incoming = try Self.decodeBackup(data)
        return try store.access(authorization: authorization, write: true) { context in
            let current = try Self.snapshot(in: context)
            let preview = Self.importPreview(incoming, current: current)
            let lists = Set(current.lists.map(\.id))
            let tasks = Set(current.tasks.map(\.id))
            let overrides = Set(current.overrides.map(\.id))
            for list in incoming.lists where !lists.contains(list.id) { try RecordCodec.write(list, in: context) }
            for task in incoming.tasks where !tasks.contains(task.id) { try RecordCodec.write(task, in: context) }
            for change in incoming.overrides where !overrides.contains(change.id) { try RecordCodec.write(change, in: context) }
            return preview
        }
    }
    private static func importPreview(_ incoming: TaskSnapshot, current: TaskSnapshot) -> ImportPreview {
        let lists = Set(current.lists.map(\.id)), tasks = Set(current.tasks.map(\.id)), overrides = Set(current.overrides.map(\.id))
        let addedLists = incoming.lists.filter { !lists.contains($0.id) }.count
        let addedTasks = incoming.tasks.filter { !tasks.contains($0.id) }.count
        let addedOverrides = incoming.overrides.filter { !overrides.contains($0.id) }.count
        return ImportPreview(newLists: addedLists, newTasks: addedTasks, newOverrides: addedOverrides,
                             skipped: incoming.lists.count + incoming.tasks.count + incoming.overrides.count - addedLists - addedTasks - addedOverrides)
    }
    private static func decodeBackup(_ data: Data) throws -> TaskSnapshot {
        guard data.count <= 50_000_000 else { throw DaydoError.invalid("备份文件超过 50 MB。") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(BackupEnvelope.self, from: data)
        guard envelope.schemaVersion == 1 else { throw DaydoError.invalid("不支持此备份版本。") }
        let snapshot = envelope.snapshot
        guard Set(snapshot.lists.map(\.id)).count == snapshot.lists.count,
              Set(snapshot.tasks.map(\.id)).count == snapshot.tasks.count,
              Set(snapshot.overrides.map(\.id)).count == snapshot.overrides.count else {
            throw DaydoError.invalid("备份包含重复的记录 ID。")
        }
        let listIDs = Set(snapshot.lists.map(\.id)), taskIDs = Set(snapshot.tasks.map(\.id))
        for list in snapshot.lists { try validateList(name: list.name, color: list.color) }
        for task in snapshot.tasks {
            _ = try task.fields.validated()
            if let listID = task.fields.listID, !listIDs.contains(listID) { throw DaydoError.invalid("备份中的清单引用无效。") }
        }
        for change in snapshot.overrides {
            guard taskIDs.contains(change.taskID) else { throw DaydoError.invalid("备份中的任务实例引用无效。") }
            if let fields = change.fields {
                _ = try fields.validated()
                if let listID = fields.listID, !listIDs.contains(listID) {
                    throw DaydoError.invalid("备份中的任务实例清单引用无效。")
                }
            }
        }
        return snapshot
    }
}
