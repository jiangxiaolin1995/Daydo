import Foundation

public enum DaydoError: Error, LocalizedError, Equatable, Sendable {
    case authenticationRequired
    case invalid(String)
    case notFound(String)
    case conflict
    case unavailable(String)

    public var code: String {
        switch self {
        case .authenticationRequired: "AUTH_REQUIRED"
        case .invalid: "INVALID_ARGUMENT"
        case .notFound: "NOT_FOUND"
        case .conflict: "VERSION_CONFLICT"
        case .unavailable: "UNAVAILABLE"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .authenticationRequired: "当前数据空间不可访问。"
        case .invalid(let message), .unavailable(let message): message
        case .notFound(let name): "找不到\(name)。"
        case .conflict: "任务已被其他操作更新，请刷新后重试。"
        }
    }
}
