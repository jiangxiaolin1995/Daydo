import Foundation

/// Local-process access depends on the selected data space, not an app login.
public struct StoreAccessGate: AuthorizationChecking {
    public let namespace: String
    private let state: @Sendable () throws -> (StoreSelection?, Bool)

    public init(namespace: String, state: @escaping @Sendable () throws -> (StoreSelection?, Bool) = {
        (try SharedEnvironment.selection(), try SharedEnvironment.isAccessLocked())
    }) {
        self.namespace = namespace
        self.state = state
    }

    public func requireAuthorization() throws {
        let (selection, locked) = try state()
        guard !locked, selection?.namespace == namespace else {
            throw DaydoError.unavailable("数据空间正在切换或尚未初始化，请打开 Daydo 后重试。")
        }
    }
}
