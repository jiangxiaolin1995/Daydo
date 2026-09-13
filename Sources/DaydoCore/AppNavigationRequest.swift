import Foundation

/// A navigation event, rather than a sticky task ID: repeated widget clicks must still be delivered.
public struct AppNavigationRequest: Equatable, Identifiable, Sendable {
    public enum Destination: Equatable, Sendable {
        case today
        case newTask
        case task(String)
    }

    public let id = UUID()
    public let destination: Destination

    public init?(url: URL) {
        guard url.scheme?.lowercased() == "daydo" else { return nil }
        let parts = url.path.split(separator: "/")
        switch url.host?.lowercased() {
        case "today" where parts.isEmpty: destination = .today
        case "new" where parts.isEmpty: destination = .newTask
        case "task":
            guard parts.count == 2, let taskID = UUID(uuidString: String(parts[0])),
                  parts[1] == "single" || LocalDay(rawValue: String(parts[1])) != nil else { return nil }
            destination = .task("\(taskID.uuidString.lowercased())/\(parts[1])")
        default: return nil
        }
    }
}
