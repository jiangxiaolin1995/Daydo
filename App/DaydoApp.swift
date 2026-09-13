import SwiftUI
import DaydoCore
import UserNotifications

@main
enum DaydoLauncher {
    @MainActor static func main() async {
        #if DEBUG
        if CommandLine.arguments.contains("--diagnose-cloud") {
            await CloudDiagnostics.run()
            return
        }
        #endif
        if CommandLine.arguments.contains("--mcp") {
            // Enter the SDK transport without creating NSApplication or a window.
            await DaydoMCP.run()
        } else { DaydoApp.main() }
    }
}

struct DaydoApp: App {
    @NSApplicationDelegateAdaptor(DaydoDelegate.self) private var delegate
    @State private var model = AppModel()
    var body: some Scene {
        Window("Daydo", id: "main") {
            AppContent().environment(model).tint(.blue)
                .frame(minWidth: 900, minHeight: 610)
                .task { if !model.hasStarted { model.hasStarted = true; await model.start() } }
                .onOpenURL { model.openURL($0) }
                .handlesExternalEvents(preferring: ["daydo://"], allowing: ["daydo://"])
        }
        .handlesExternalEvents(matching: ["daydo://"])
        .defaultSize(width: 1160, height: 780)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("撤销上一步") { Task { await model.undo() } }
                    .keyboardShortcut("z").disabled(!model.canUndo)
            }
        }
        Settings {
            SettingsView().environment(model).tint(.blue).frame(width: 620, height: 610)
        }
        MenuBarExtra {
            DaydoMenu().environment(model)
        } label: {
            DaydoMenuLabel().environment(model)
        }
    }
}

private struct AppContent: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Group {
            if model.isLoading { ProgressView("正在打开 Daydo…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if model.isReady { RootView() }
            else {
                ContentUnavailableView {
                    Label("暂时无法打开任务", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(model.errorMessage ?? "请重试打开本机任务存储。")
                } actions: {
                    Button("重试") { Task { await model.retryOpen() } }
                }
            }
        }
        .preferredColorScheme(model.isPreview && CommandLine.arguments.contains("--preview-dark") ? .dark : nil)
        .alert("Daydo", isPresented: Binding(get: { model.errorMessage != nil },
                                             set: { if !$0 { model.errorMessage = nil } })) {
            Button("好") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct DaydoMenuLabel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var handledLaunch = false

    var body: some View {
        Image(systemName: "checkmark.square").accessibilityLabel("Daydo")
            .task {
                guard !handledLaunch else { return }
                handledLaunch = true
                if !CommandLine.arguments.contains("--background") { openWindow(id: "main") }
                // A windowless coordinator must still load data, sync, and maintain reminders.
                if !model.hasStarted { model.hasStarted = true; await model.start() }
            }
    }
}

private struct DaydoMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("打开 Daydo") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        if model.isReady {
            Button("新建任务") {
                openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                model.requestNewTask = true
            }
            let today = OccurrenceEngine.expand(model.snapshot, from: .today(), through: .today())
            Text("今天还有 \(today.filter { !$0.isCompleted }.count) 项")
        }
        Divider()
        SettingsLink { Text("设置…") }
        Button("退出 Daydo") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

final class DaydoDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        if CommandLine.arguments.contains("--background") {
            DispatchQueue.main.async { NSApp.hide(nil) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = sender.windows.first(where: {
            $0.identifier?.rawValue == "main" || $0.identifier?.rawValue.hasPrefix("main-") == true
        }) {
            if !flag { window.makeKeyAndOrderFront(nil) }
            // We handled the reopen; do not also request a new untitled SwiftUI scene.
            return false
        }
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: raw) else { return }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
