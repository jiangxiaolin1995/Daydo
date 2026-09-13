import AppIntents
import Foundation
import WidgetKit
import DaydoCore
import OSLog

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "完成 Daydo 任务"
    static let description = IntentDescription("完成一个待办任务或指定的重复实例。")
    static var openAppWhenRun: Bool { false }
    @available(macOS 26.0, *)
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "任务 ID") var taskID: String
    @Parameter(title: "发生日期") var occurrenceDay: String

    init() {}
    init(taskID: String, occurrenceDay: String) { self.taskID = taskID; self.occurrenceDay = occurrenceDay }
    func perform() async throws -> some IntentResult {
        let log = Logger(subsystem: DaydoConstants.bundleID, category: "Widget")
        log.notice("Completion started in \(ProcessInfo.processInfo.processName, privacy: .public)")
        guard let id = UUID(uuidString: taskID) else { throw DaydoError.invalid("无效的任务 ID。") }
        if let selected = try SharedEnvironment.selection(), selected.cloudEnabled {
            let account = await CloudAccountService.resolve(previous: selected, allowCached: true)
            guard account.selection == selected else {
                try SharedEnvironment.setAccessLocked(true)
                WidgetCenter.shared.reloadAllTimelines()
                throw DaydoError.unavailable("系统 iCloud 账户已变化，请打开 Daydo 后重试。")
            }
        }
        let repository = try SharedEnvironment.repository()
        defer { try? repository.close() }
        try repository.setCompletion(id: id, completed: true, originalDay: LocalDay(rawValue: occurrenceDay), source: "widget")
        log.notice("Completion saved")
        #if !WIDGET_EXTENSION
        if let selection = try SharedEnvironment.selection() {
            let enabled = UserDefaults.standard.object(forKey: "remindersEnabled") as? Bool ?? true
            try await NotificationService().reconcile(repository.snapshot(), namespace: selection.namespace, enabled: enabled)
        }
        #endif
        WidgetCenter.shared.reloadTimelines(ofKind: DaydoConstants.widgetKind)
        return .result()
    }
}

// Completion runs in the widget extension. Shared-store notifications let the existing
// background coordinator refresh reminders without opening a window.
