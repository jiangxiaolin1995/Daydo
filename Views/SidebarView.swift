import SwiftUI
import DaydoCore

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: String?
    var editList: (TodoList?) -> Void
    private var pendingCount: Int { model.snapshot.tasks.filter { !$0.isDeleted && $0.completedAt == nil }.count }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image("DaydoIcon").resizable().frame(width: 32, height: 32)
                Text("Daydo").font(.system(size: 18, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 15).padding(.top, 16).padding(.bottom, 18)
            List(selection: $selection) {
                nav("收集箱", icon: "tray", value: "inbox", count: model.snapshot.tasks.filter { !$0.isDeleted && $0.fields.day == nil && $0.completedAt == nil }.count)
                nav("今天", icon: "sun.max", value: "today", count: todayCount)
                nav("未来", icon: "calendar.badge.clock", value: "upcoming", count: nil)
                nav("日历", icon: "calendar", value: "calendar", count: nil)
                Section {
                    ForEach(model.snapshot.lists.filter { !$0.isArchived }) { list in
                        HStack(spacing: 10) {
                            Image(systemName: "number").foregroundStyle(DaydoStyle.color(list.color))
                            Text(list.name).lineLimit(1)
                            Spacer()
                            let count = model.snapshot.tasks.filter { $0.fields.listID == list.id && !$0.isDeleted && $0.completedAt == nil }.count
                            if count > 0 { Text("\(count)").font(.caption).foregroundStyle(.secondary) }
                        }
                        .tag("list:\(list.id.uuidString)")
                        .contextMenu {
                            Button("编辑清单") { editList(list) }
                            Button("向上移动") { move(list, delta: -1) }
                            Button("向下移动") { move(list, delta: 1) }
                            Divider()
                            Button("归档清单") {
                                var updated = list; updated.isArchived = true
                                let changed = updated
                                Task { _ = await model.run { try $0.updateList(changed, expectedRevision: list.revision) } }
                            }
                        }
                    }
                    Button { editList(nil) } label: {
                        Label("新建清单", systemImage: "plus").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("new-list")
                } header: {
                    Text("我的清单").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                Section {
                    nav("已完成", icon: "checkmark.circle", value: "completed", count: nil)
                    nav("已删除", icon: "trash", value: "trash", count: nil)
                }
            }
            .listStyle(.sidebar)
            Spacer(minLength: 0)
            HStack(spacing: 9) {
                Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isPreview ? "界面预览" : "我的 Daydo").font(.caption.weight(.medium)).lineLimit(1)
                    Text(model.isPreview ? "独立界面预览" : (model.activeSelection?.cloudEnabled == true ? "iCloud 同步" : "保存在本机"))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                SettingsLink { Image(systemName: "gearshape").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("设置").accessibilityIdentifier("open-settings")
            }
            .padding(16)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 280)
    }
    private var todayCount: Int {
        let today = LocalDay(model.lastRefresh)
        let earliest = min(model.snapshot.tasks.compactMap(\.fields.day).min() ?? today, today)
        return OccurrenceEngine.expand(model.snapshot, from: earliest, through: today).filter { !$0.isCompleted }.count
    }
    private func nav(_ title: String, icon: String, value: String, count: Int?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 17).foregroundStyle(selection == value ? .blue : .secondary)
            Text(title)
            Spacer()
            if let count, count > 0 { Text("\(count)").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 3).tag(value)
    }
    private func move(_ list: TodoList, delta: Int) {
        let ordered = model.snapshot.lists.filter { !$0.isArchived }
        guard let index = ordered.firstIndex(where: { $0.id == list.id }), ordered.indices.contains(index + delta) else { return }
        var changed = list
        changed.order = ordered[index + delta].order + (delta < 0 ? -0.5 : 0.5)
        let updated = changed
        Task { _ = await model.run { try $0.updateList(updated, expectedRevision: list.revision) } }
    }
}

struct ListEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var list: TodoList?
    @State private var name: String
    @State private var color: String
    @State private var isSaving = false
    init(list: TodoList?) {
        self.list = list
        _name = State(initialValue: list?.name ?? "")
        _color = State(initialValue: list?.color ?? "#2563EB")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(list == nil ? "新建清单" : "编辑清单").font(.title2.weight(.semibold))
            TextField("清单名称", text: $name).textFieldStyle(.roundedBorder).onSubmit { save() }
            HStack(spacing: 12) {
                ForEach(DaydoStyle.colors, id: \.self) { value in
                    Button { color = value } label: {
                        Circle().fill(DaydoStyle.color(value)).frame(width: 24, height: 24)
                            .overlay { if value == color { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                    }.buttonStyle(.plain).accessibilityLabel("颜色 \(value)")
                }
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }.padding(26).frame(width: 350)
    }
    private func save() {
        isSaving = true
        let name = name, color = color
        Task {
            let result: TodoList?
            if var existing = list {
                let revision = existing.revision
                existing.name = name; existing.color = color
                let updated = existing
                result = await model.run { try $0.updateList(updated, expectedRevision: revision) }
            } else { result = await model.run { try $0.createList(name: name, color: color) } }
            isSaving = false
            if result != nil { dismiss() }
        }
    }
}
