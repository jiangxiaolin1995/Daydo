#if DEBUG
import Foundation
import DaydoCore

private struct PreviewAuthorization: AuthorizationChecking {
    func requireAuthorization() throws {}
}

extension AppModel {
    func startPreview() async {
        isPreview = true
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("DaydoPreview-\(ProcessInfo.processInfo.processIdentifier)/Daydo.sqlite")
            repository = try TaskRepository(storeURL: url, authorization: PreviewAuthorization())
            guard let repository else { return }
            let today = LocalDay.today()
            let work = try repository.createList(name: "工作", color: "#2563EB")
            let life = try repository.createList(name: "生活", color: "#F59E0B")
            let learning = try repository.createList(name: "学习", color: "#8B5CF6")
            _ = try repository.createTask(fields: TaskFields(title: "整理本周的项目计划", notes: "把重要的事情留出完整的时间，明确下一步。",
                                                            listID: work.id, day: today, startMinute: 9 * 60, durationMinutes: 60, priority: .high))
            _ = try repository.createTask(fields: TaskFields(title: "产品方案评审", notes: "确认核心流程、设计细节与验收标准。",
                                                            listID: work.id, day: today, startMinute: 14 * 60, durationMinutes: 90, reminderMinutesBefore: 15))
            _ = try repository.createTask(fields: TaskFields(title: "读书 30 分钟", listID: learning.id, day: today,
                                                            startMinute: 20 * 60, repeatRule: .init(kind: .daily)))
            _ = try repository.createTask(fields: TaskFields(title: "给绿植浇水", listID: life.id, day: today))
            _ = try repository.createTask(fields: TaskFields(title: "预约周末的徒步", listID: life.id, day: today.adding(days: 2)))
            _ = try repository.createTask(fields: TaskFields(title: "一个值得慢慢完善的新想法", notes: "先记录下来，合适的时候再安排。"))
            _ = try repository.createTask(fields: TaskFields(title: "回复合作邮件", listID: work.id, day: today.adding(days: -1), priority: .medium))
            let done = try repository.createTask(fields: TaskFields(title: "晨间散步", listID: life.id, day: today, startMinute: 7 * 60))
            try repository.setCompletion(id: done.id, completed: true)
            cloudStatus = "独立预览数据 · 不连接 iCloud"
            isLoading = false
            await refresh()
        } catch { errorMessage = error.localizedDescription; isLoading = false }
    }
}
#endif
