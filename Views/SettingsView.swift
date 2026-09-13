import SwiftUI
import UniformTypeIdentifiers
import DaydoCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0
    @State private var pendingImport: Data?
    @State private var importPreview: ImportPreview?
    @State private var message: String?
    var body: some View {
        TabView(selection: $tab) {
            account.tabItem { Label("iCloud", systemImage: "icloud") }.tag(0)
            general.tabItem { Label("通用", systemImage: "gearshape") }.tag(1)
            AgentSettingsView().tabItem { Label("Agent", systemImage: "terminal") }.tag(2)
            data.tabItem { Label("数据", systemImage: "externaldrive") }.tag(3)
        }.padding(20)
        .alert("导入备份", isPresented: Binding(get: { importPreview != nil }, set: { if !$0 { importPreview = nil; pendingImport = nil } })) {
            Button("取消", role: .cancel) { pendingImport = nil; importPreview = nil }
            Button("导入") {
                if let data = pendingImport {
                    Task {
                        if await model.run({ try $0.importBackup(data) }) != nil { message = "备份已导入。" }
                    }
                }
                pendingImport = nil; importPreview = nil
            }
        } message: {
            if let preview = importPreview {
                Text("新增 \(preview.newLists) 个清单、\(preview.newTasks) 个任务、\(preview.newOverrides) 条实例记录。跳过 \(preview.skipped) 条已有记录，保留当前修改。")
            }
        }
        .alert("Daydo", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") { message = nil }
        } message: { Text(message ?? "") }
    }
    private var account: some View {
        Form {
            Section("数据存储") {
                LabeledContent("使用方式", value: "免登录，本机可用")
                Text("打开 Daydo 就能记录任务，无需单独创建或登录账户。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("系统 iCloud") {
                LabeledContent("同步状态", value: model.cloudStatus)
                Text("同步跟随这台 Mac 的系统 iCloud 账户。未启用 iCloud 时，任务保存在本机。后台同步可能需要一些时间。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.pendingCloudSelection != nil {
                    Text("启用后，本机任务会合并到当前系统 iCloud 账户。").font(.callout)
                    Button("将本机任务合并到 iCloud") { Task { await model.migrateLocalToCloud() } }
                }
                Button("重新检查 iCloud") { Task { await model.checkCloudAccount() } }.disabled(!model.isReady || model.isPreview)
            }
        }.formStyle(.grouped)
    }
    private var general: some View {
        Form {
            Section("后台与提醒") {
                Toggle("开机启动 Daydo", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                    .disabled(model.isPreview)
                Toggle("允许任务提醒", isOn: Binding(get: { model.remindersEnabled }, set: { enabled in Task { await model.setReminderEnabled(enabled) } }))
                    .disabled(!model.isReady || model.isPreview)
                LabeledContent("系统通知权限", value: model.notificationPermission ? "已允许" : "尚未允许")
                if !model.notificationPermission {
                    Button("允许系统通知…") { Task { await model.setReminderEnabled(true) } }
                        .disabled(!model.isReady || model.isPreview)
                }
                Text("关掉窗口后，Daydo 会继续在菜单栏运行，处理同步和提醒。完全退出后，已安排的系统提醒仍会投递。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("操作") {
                LabeledContent("新增任务", value: "⌘N")
                LabeledContent("搜索", value: "⌘F")
                LabeledContent("完成选中任务", value: "⌘↩")
                LabeledContent("撤销上一步", value: "⌘Z")
            }
            Section("外观") { Text("跟随 macOS 的浅色或深色外观。日历默认周一开始，时间安排以 15 分钟为单位。").foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }
    private var data: some View {
        Form {
            Section("备份与恢复") {
                Text("导出版本化 JSON 备份。导入前先预览；相同 ID 的现有记录会保留。").foregroundStyle(.secondary)
                HStack {
                    Button("导出备份…") { exportBackup() }
                    Button("导入备份…") { importBackup() }
                }.disabled(!model.isReady)
            }
            Section("已归档的清单") {
                let archived = model.snapshot.lists.filter(\.isArchived)
                if archived.isEmpty { Text("暂无归档清单").foregroundStyle(.secondary) }
                ForEach(archived) { list in
                    HStack {
                        Text(list.name); Spacer()
                        Button("恢复") {
                            var updated = list; updated.isArchived = false
                            let value = updated
                            Task { _ = await model.run { try $0.updateList(value, expectedRevision: list.revision) } }
                        }
                    }
                }
            }
        }.formStyle(.grouped)
    }
    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Daydo-\(LocalDay.today()).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let data = await model.run({ try $0.exportBackup() }) {
                do { try data.write(to: url, options: .atomic); message = "备份已导出。" }
                catch { message = error.localizedDescription }
            }
        }
    }
    private func importBackup() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let repository = model.repository else { return }
            importPreview = try repository.previewImport(data); pendingImport = data
        } catch { message = error.localizedDescription }
    }
}
