import Foundation
import AppKit
import MCP
import DaydoCore
import WidgetKit

enum DaydoMCP {
    static func run() async {
        let client = ClientIdentity()
        let server = Server(name: "daydo", version: "1.0.0", instructions:
            "Daydo manages local personal tasks without app sign-in. Call get_status first and check ready. iCloud uses the Mac system account. Dates are YYYY-MM-DD; fields.timeZoneID is an IANA timezone. Repeat instances use taskId + occurrenceDay (the original scheduled day). Use explicit completed booleans, unique requestId for creates and expectedRevision from current records for edits.",
                            capabilities: .init(tools: .init(listChanged: false)), configuration: .strict)
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: try MCPToolCatalog.tools()) }
        await server.withMethodHandler(CallTool.self) { parameters in
            do {
                let data: Data
                if parameters.name == "get_status" {
                    guard parameters.arguments?.isEmpty != false else { throw DaydoError.invalid("get_status 不接受参数。") }
                    data = try status()
                } else {
                    try await checkSystemAccount()
                    let repository = try SharedEnvironment.repository()
                    defer { try? repository.close() }
                    data = try AgentCommands(repository: repository).handle(parameters.name,
                        arguments: JSONEncoder().encode(parameters.arguments ?? [:]), source: await client.source)
                    // The GUI process owns CloudKit and notification scheduling.
                    if ["create_list", "update_list", "create_task", "update_task", "set_task_completion"].contains(parameters.name) {
                        await wakeCoordinator()
                    }
                }
                diagnostic("\(await client.source) \(parameters.name): OK")
                return .init(content: [.text(String(decoding: data, as: UTF8.self))], isError: false)
            } catch {
                let code = (error as? DaydoError)?.code ?? "UNAVAILABLE"
                diagnostic("\(parameters.name): \(code)")
                let data = (try? JSONSerialization.data(withJSONObject: ["code": code, "message": error.localizedDescription], options: [.sortedKeys])) ?? Data()
                return .init(content: [.text(String(decoding: data, as: UTF8.self))], isError: true)
            }
        }
        do {
            try await server.start(transport: CompatibleStdioTransport()) { info, _ in await client.set(info.name) }
            await server.waitUntilCompleted()
            await server.stop()
        } catch { diagnostic("Server stopped: \(error.localizedDescription)") }
    }
    static func checkSystemAccount() async throws {
        guard let selected = try SharedEnvironment.selection() else {
            await wakeCoordinator()
            throw DaydoError.unavailable("Daydo 正在初始化本机存储，请稍后重试。")
        }
        let initiallyLocked = try SharedEnvironment.isAccessLocked()
        guard selected.cloudEnabled || initiallyLocked else { return }
        let resolved = await CloudAccountService.resolve(previous: selected, allowCached: true)
        guard let current = try SharedEnvironment.selection() else { throw DaydoError.unavailable("本机存储尚未初始化。") }
        let stillLocked = try SharedEnvironment.isAccessLocked()
        if (current.cloudEnabled && current != resolved.selection) || stillLocked {
            try SharedEnvironment.setAccessLocked(true)
            WidgetCenter.shared.reloadAllTimelines()
            await wakeCoordinator()
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.xiaolin.daydo.account-check"), object: nil, userInfo: nil, deliverImmediately: true)
            throw DaydoError.unavailable("系统 iCloud 账户已变化。Daydo 正在切换数据空间，请稍后重试。")
        }
    }
    static func status() throws -> Data {
        var value: [String: Any] = ["app": "Daydo", "version": "1.0.0", "timeZoneID": TimeZone.current.identifier,
                                   "today": LocalDay.today().rawValue, "transport": "stdio"]
        do {
            let locked = try SharedEnvironment.isAccessLocked()
            let selection = try SharedEnvironment.selection()
            value["ready"] = selection != nil && !locked
            value["signInRequired"] = false
            value["storage"] = selection?.cloudEnabled == true ? "system_iCloud" : "local"
            value["sync"] = selection?.cloudEnabled == true ? "managed_by_main_app" : "local_only"
            if !locked, let status = try SharedEnvironment.coordinatorStatus() {
                value["syncMessage"] = status.syncMessage
                value["notificationAuthorized"] = status.notificationAuthorized
                value["coordinatorUpdatedAt"] = ISO8601DateFormatter().string(from: status.updatedAt)
            }
            value["message"] = selection == nil || locked ? "请打开 Daydo 完成本机存储初始化或账户切换。" : "免登录使用。iCloud 跟随系统账户，后台同步不保证即时到达。"
        } catch {
            value["ready"] = false; value["signInRequired"] = false
            value["code"] = "UNAVAILABLE"; value["message"] = error.localizedDescription
        }
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    @MainActor static func wakeCoordinator() async {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: DaydoConstants.bundleID)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && $0.activationPolicy == .regular }
        guard !running else { return }
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false; configuration.addsToRecentItems = false
        configuration.arguments = ["--background"]
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
    static func diagnostic(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("[Daydo MCP] \(message)\n".utf8))
    }
}

private actor ClientIdentity {
    var source = "mcp"
    func set(_ name: String) { source = "mcp:" + String(name.filter { !$0.isNewline }.prefix(80)) }
}
