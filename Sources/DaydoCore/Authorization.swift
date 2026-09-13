import Foundation

public protocol AuthorizationChecking: Sendable {
    func requireAuthorization() throws
}

public struct ClosedAuthorization: AuthorizationChecking {
    public init() {}
    public func requireAuthorization() throws { throw DaydoError.authenticationRequired }
}
