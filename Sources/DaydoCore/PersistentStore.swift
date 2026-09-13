import Foundation
@preconcurrency import CoreData
import Darwin

final class PersistentStore: @unchecked Sendable {
    let container: NSPersistentContainer
    private let processLock = NSRecursiveLock()
    private let lockURL: URL
    private let storeURL: URL
    private var isClosed = false

    init(url: URL, cloudContainerID: String?) throws {
        storeURL = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        lockURL = url.appendingPathExtension("commands.lock")
        if let cloudContainerID {
            container = NSPersistentCloudKitContainer(name: "Daydo", managedObjectModel: Self.model())
            let description = NSPersistentStoreDescription(url: url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerID)
            container.persistentStoreDescriptions = [description]
        } else {
            container = NSPersistentContainer(name: "Daydo", managedObjectModel: Self.model())
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        }
        let description = container.persistentStoreDescriptions[0]
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
    }

    func access<T: Sendable>(authorization: any AuthorizationChecking, write: Bool,
                   _ body: @Sendable (NSManagedObjectContext) throws -> T) throws -> T {
        try authorization.requireAuthorization()
        processLock.lock()
        defer { processLock.unlock() }
        guard !isClosed else { throw DaydoError.unavailable("此账户的数据存储已关闭。") }
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw DaydoError.unavailable("无法锁定任务存储。") }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw DaydoError.unavailable("任务存储忙，请重试。") }
        defer { flock(descriptor, LOCK_UN) }
        try authorization.requireAuthorization()
        let context = container.newBackgroundContext()
        context.mergePolicy = NSErrorMergePolicy
        context.transactionAuthor = write ? "daydo.command" : "daydo.read"
        do {
            let result = try context.performAndWait {
                try context.setQueryGenerationFrom(.current)
                let result = try body(context)
                if write {
                    try authorization.requireAuthorization()
                    if context.hasChanges { try context.save() }
                }
                return result
            }
            if write { Self.signalChange() }
            return result
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && (error.code == NSManagedObjectMergeError || error.code == NSPersistentStoreSaveConflictsError) {
                throw DaydoError.conflict
            }
            throw error
        }
    }

    func close() throws {
        processLock.lock()
        defer { processLock.unlock() }
        guard !isClosed else { return }
        let coordinator = container.persistentStoreCoordinator
        try coordinator.performAndWait {
            for store in coordinator.persistentStores { try coordinator.remove(store) }
        }
        isClosed = true
    }

    func consumeHistory(authorization: any AuthorizationChecking, consumer: String) throws -> Int {
        guard consumer.range(of: "^[a-zA-Z0-9-]{1,40}$", options: .regularExpression) != nil else {
            throw DaydoError.invalid("无效的历史消费者名称。")
        }
        let tokenURL = storeURL.appendingPathExtension("history-\(consumer)")
        return try access(authorization: authorization, write: false) { context in
            let token: NSPersistentHistoryToken?
            if let data = try? Data(contentsOf: tokenURL) {
                token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
            } else { token = nil }
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            request.resultType = .transactionsOnly
            let result = try context.execute(request) as? NSPersistentHistoryResult
            let transactions = result?.result as? [NSPersistentHistoryTransaction] ?? []
            if let latest = transactions.last?.token {
                try NSKeyedArchiver.archivedData(withRootObject: latest, requiringSecureCoding: true).write(to: tokenURL, options: .atomic)
            }
            return transactions.count
        }
    }

    static func signalChange() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.xiaolin.daydo.changed"), object: nil, userInfo: nil, deliverImmediately: true)
    }

    private static func model() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let string = NSAttributeType.stringAttributeType
        let date = NSAttributeType.dateAttributeType
        let integer = NSAttributeType.integer64AttributeType
        let boolean = NSAttributeType.booleanAttributeType
        let common: [(String, NSAttributeType)] = [("stableID", string), ("modifiedAt", date), ("revision", string)]
        func entity(_ name: String, _ fields: [(String, NSAttributeType)]) -> NSEntityDescription {
            let entity = NSEntityDescription()
            entity.name = name
            entity.managedObjectClassName = "NSManagedObject"
            entity.properties = (common + fields).map { key, type in
                let attribute = NSAttributeDescription()
                attribute.name = key
                attribute.attributeType = type
                attribute.isOptional = true
                return attribute
            }
            return entity
        }
        model.entities = [
            entity("DDList", [("name", string), ("color", string), ("sortOrder", .doubleAttributeType), ("isArchived", boolean)]),
            entity("DDTask", [
                ("title", string), ("notes", string), ("listID", string), ("day", string), ("startMinute", integer),
                ("durationMinutes", integer), ("timeZoneID", string), ("priority", integer),
                ("repeatKind", string), ("repeatWeekdays", string), ("repeatUntil", string),
                ("reminderLead", integer), ("reminderMinute", integer), ("completedAt", date),
                ("deletedFlag", boolean), ("createdAt", date), ("source", string)
            ]),
            entity("DDOccurrence", [
                ("taskID", string), ("originalDay", string), ("fields", .binaryDataAttributeType),
                ("completedAt", date), ("deletedFlag", boolean), ("source", string)
            ]),
            entity("DDReceipt", [("fingerprint", string), ("resultID", string)])
        ]
        return model
    }
}
