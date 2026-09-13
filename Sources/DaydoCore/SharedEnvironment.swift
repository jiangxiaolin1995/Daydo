import Foundation

public enum DaydoConstants {
    public static let bundleID = "com.xiaolin.daydo"
    public static let cloudContainerID = "iCloud.com.xiaolin.daydo"
    public static let appGroupID = "2S5P3UNGAL.com.xiaolin.daydo"
    public static let changeNotification = "com.xiaolin.daydo.changed"
    public static let widgetKind = "DaydoToday"
}

public struct StoreSelection: Codable, Equatable, Sendable {
    public var namespace: String
    public var cloudEnabled: Bool
    public init(namespace: String, cloudEnabled: Bool) { self.namespace = namespace; self.cloudEnabled = cloudEnabled }

    /// Check a cached cloud identity before exposing its data on a cold launch.
    /// A first local launch needs no network; an interrupted account switch must resolve fresh.
    public static func forStartup(previous: StoreSelection?, accessLocked: Bool, local: StoreSelection,
                                  resolveAccount: @Sendable (StoreSelection, Bool) async -> StoreSelection) async -> StoreSelection {
        let initial = previous ?? local
        guard initial.cloudEnabled || accessLocked else { return initial }
        return await resolveAccount(initial, !accessLocked)
    }
}

public struct CoordinatorStatus: Codable, Sendable {
    public var namespace: String
    public var syncMessage: String
    public var notificationAuthorized: Bool
    public var updatedAt: Date
    public init(namespace: String, syncMessage: String, notificationAuthorized: Bool) {
        self.namespace = namespace; self.syncMessage = syncMessage
        self.notificationAuthorized = notificationAuthorized; updatedAt = Date()
    }
}

public enum SharedEnvironment {
    public static func publishStatus(_ status: CoordinatorStatus) throws {
        try StoreAccessGate(namespace: status.namespace).requireAuthorization()
        try JSONEncoder().encode(status).write(to: root().appendingPathComponent("coordinator-status.json"), options: .atomic)
    }
    public static func coordinatorStatus() throws -> CoordinatorStatus? {
        let url = try root().appendingPathComponent("coordinator-status.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try JSONDecoder().decode(CoordinatorStatus.self, from: Data(contentsOf: url))
        return value.namespace == (try selection()?.namespace) ? value : nil
    }
    public static func root() throws -> URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DaydoConstants.appGroupID) else {
            throw DaydoError.unavailable("共享数据容器不可用，请检查 Daydo 的 App Group 签名。")
        }
        let directory = url.appendingPathComponent("Library/Application Support/Daydo", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    public static func selection() throws -> StoreSelection? {
        let url = try root().appendingPathComponent("active-store.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let selection = try JSONDecoder().decode(StoreSelection.self, from: Data(contentsOf: url))
        guard selection.namespace.range(of: "^(local|icloud)-[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw DaydoError.unavailable("数据空间标识无效。")
        }
        return selection
    }
    public static func select(_ selection: StoreSelection) throws {
        let url = try root().appendingPathComponent("active-store.json")
        try JSONEncoder().encode(selection).write(to: url, options: .atomic)
    }
    public static func namespace(for identifier: String, cloud: Bool) -> String {
        (cloud ? "icloud-" : "local-") + TaskRepository.hash(identifier)
    }
    public static func storeURL(_ selection: StoreSelection) throws -> URL {
        try root().appendingPathComponent("Stores", isDirectory: true)
            .appendingPathComponent(selection.namespace, isDirectory: true).appendingPathComponent("Daydo.sqlite")
    }
    public static func setAccessLocked(_ locked: Bool) throws {
        let url = try root().appendingPathComponent("access-locked")
        if locked { try Data().write(to: url, options: .atomic) }
        else if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        signalChange()
    }
    public static func isAccessLocked() throws -> Bool {
        FileManager.default.fileExists(atPath: try root().appendingPathComponent("access-locked").path)
    }
    public static func repository(cloud: Bool = false) throws -> TaskRepository {
        guard try !isAccessLocked() else { throw DaydoError.unavailable("数据空间正在切换，请稍后重试。") }
        guard let selection = try selection() else { throw DaydoError.unavailable("请先打开 Daydo 完成初始化。") }
        return try TaskRepository(storeURL: storeURL(selection), authorization: StoreAccessGate(namespace: selection.namespace),
                                  cloudContainerID: cloud && selection.cloudEnabled ? DaydoConstants.cloudContainerID : nil)
    }
    public static func signalChange() { PersistentStore.signalChange() }
}
