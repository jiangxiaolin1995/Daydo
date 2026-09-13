import SwiftUI
import DaydoCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @SceneStorage("sidebar") private var savedSelection = "today"
    @State private var selectedTaskID: String?
    @State private var search = ""
    @State private var searchPresented = false
    @State private var showInspector = false
    @State private var newTask: NewTaskDraft?
    @State private var listSheet: ListSheet?
    @FocusState private var quickAddFocused: Bool
    @State private var quickTitle = ""

    private var selection: Binding<String?> {
        Binding(get: { savedSelection }, set: { savedSelection = $0 ?? "today"; selectedTaskID = nil })
    }
    private var selectedList: TodoList? {
        guard savedSelection.hasPrefix("list:") else { return nil }
        return model.snapshot.lists.first { $0.id.uuidString == String(savedSelection.dropFirst(5)) }
    }
    private var title: String {
        if !search.isEmpty { return "搜索结果" }
        return switch savedSelection {
        case "inbox": "收集箱"
        case "today": "今天"
        case "upcoming": "未来"
        case "calendar": "日历"
        case "completed": "已完成"
        case "trash": "已删除"
        default: selectedList?.name ?? "任务"
        }
    }
    private var items: [TaskOccurrence] {
        let today = LocalDay(model.lastRefresh)
        let earliest = model.snapshot.tasks.compactMap(\.fields.day).min() ?? today
        let latest = model.snapshot.tasks.compactMap(\.fields.day).max() ?? today
        let from = search.isEmpty && savedSelection == "upcoming" ? today.adding(days: 1) : earliest
        let through = search.isEmpty && savedSelection == "today" ? today : max(today.adding(days: 90), latest)
        var rows = OccurrenceEngine.expand(model.snapshot, from: min(from, through), through: through, includeUndated: true)
        switch search.isEmpty ? savedSelection : "search" {
        case "inbox": rows = rows.filter { $0.fields.day == nil && !$0.isCompleted }
        case "today": rows = rows.filter { $0.fields.day != nil && ($0.fields.day == today || !$0.isCompleted) }
        case "upcoming": rows = rows.filter { $0.fields.day != nil && !$0.isCompleted }
        case "completed": rows = rows.filter(\.isCompleted)
        default:
            if search.isEmpty, let list = selectedList { rows = rows.filter { $0.fields.listID == list.id } }
        }
        if !search.isEmpty {
            rows = rows.filter { $0.fields.title.localizedCaseInsensitiveContains(search) || $0.fields.notes.localizedCaseInsensitiveContains(search) }
        }
        return rows
    }
    private var selectedOccurrence: TaskOccurrence? {
        guard let selectedTaskID else { return nil }
        if let item = items.first(where: { $0.id == selectedTaskID }) { return item }
        return findOccurrence(selectedTaskID)
    }
    var body: some View {
        NavigationSplitView {
            SidebarView(selection: selection) { list in listSheet = ListSheet(list: list) }
        } detail: {
            VStack(spacing: 0) {
                if model.isPreview {
                    Text("界面预览 · 使用独立演示数据，不连接 iCloud 或 MCP")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(7).background(.orange.opacity(0.08))
                }
                if savedSelection == "calendar" && search.isEmpty {
                    CalendarView(selectedID: $selectedTaskID, query: search, onCreate: { day, minute in
                        newTask = NewTaskDraft(fields: TaskFields(title: "", day: day, startMinute: minute))
                    }, onSelect: { _ in showInspector = true })
                } else if savedSelection == "trash" && search.isEmpty {
                    trash
                } else {
                    taskList
                }
            }
            .inspector(isPresented: $showInspector) {
                if let occurrence = selectedOccurrence {
                    TaskEditor(occurrence: occurrence, initial: occurrence.fields) { showInspector = false }
                        .id(occurrence.id).inspectorColumnWidth(min: 280, ideal: 310, max: 390)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sidebar.right").font(.largeTitle).foregroundStyle(.tertiary)
                        Text("选择一项任务查看详情").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Daydo")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { addTask() } label: { Label("新建任务", systemImage: "plus") }
                    .keyboardShortcut("n").help("新建任务 ⌘N").accessibilityIdentifier("new-task")
                Button { showInspector.toggle() } label: { Label("任务详情", systemImage: "sidebar.right") }
                    .help("任务详情")
            }
        }
        .searchable(text: $search, isPresented: $searchPresented, placement: .toolbar, prompt: "搜索任务")
        .sheet(item: $newTask) { draft in
            TaskEditor(occurrence: nil, initial: draft.fields) { newTask = nil }.frame(width: 430, height: 650)
        }
        .sheet(item: $listSheet) { sheet in ListEditor(list: sheet.list) }
        .onChange(of: selectedTaskID) { _, value in if value != nil { showInspector = true } }
        .onChange(of: model.navigationRequest, initial: true) { _, request in
            guard let request else { return }
            search = ""
            switch request.destination {
            case .today:
                savedSelection = "today"; selectedTaskID = nil; showInspector = false
            case .newTask:
                savedSelection = "today"; addTask()
            case .task(let id):
                selectedTaskID = id; showInspector = true
            }
            model.navigationRequest = nil
        }
        .onChange(of: model.requestNewTask) { _, value in
            if value { addTask(); model.requestNewTask = false }
        }
        .background {
            VStack {
                Button("搜索任务") { searchPresented = true }.keyboardShortcut("f")
                Button("完成选中任务") {
                    if let selectedOccurrence { Task { await model.complete(selectedOccurrence) } }
                }.keyboardShortcut(.return, modifiers: .command)
            }.hidden()
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.system(size: 28, weight: .semibold))
                    HStack(spacing: 8) {
                        if savedSelection == "today" { Text(Date(), format: .dateTime.month(.wide).day().weekday(.wide)) }
                        Text("\(items.filter { !$0.isCompleted }.count) 项待完成")
                    }.font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if savedSelection == "today", !items.isEmpty {
                    let completed = items.filter(\.isCompleted).count
                    ZStack {
                        Circle().stroke(.blue.opacity(0.1), lineWidth: 4)
                        Circle().trim(from: 0, to: CGFloat(completed) / CGFloat(items.count))
                            .stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        Text("\(completed)/\(items.count)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    }.frame(width: 43, height: 43)
                }
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 22)
            if savedSelection != "completed" {
                HStack(spacing: 11) {
                    Image(systemName: "plus").foregroundStyle(.blue)
                    TextField("添加任务，按回车保存", text: $quickTitle)
                        .textFieldStyle(.plain).font(.system(size: 14)).focused($quickAddFocused)
                        .onSubmit { quickAdd() }.accessibilityIdentifier("quick-add")
                }
                .padding(13).background(.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.blue.opacity(0.08)))
                .padding(.horizontal, 26).padding(.bottom, 14)
            }
            if items.isEmpty {
                EmptyTasksView(title: search.isEmpty ? "给今天留一点空间" : "没有找到相关任务",
                               message: search.isEmpty ? "从一件小事开始，让想法有个着落。" : "试试其他关键词。", action: addTask)
            } else {
                List(selection: $selectedTaskID) {
                    let overdue = items.filter { ($0.fields.day ?? .today()) < .today() && !$0.isCompleted }
                    let pending = items.filter { !$0.isCompleted && !overdue.contains($0) }
                    let completed = items.filter(\.isCompleted)
                    if !overdue.isEmpty {
                        Section("逾期 · \(overdue.count)") { ForEach(overdue) { TaskRow(occurrence: $0, showDate: true).tag($0.id) } }
                    }
                    if !pending.isEmpty {
                        Section(savedSelection == "today" ? "今天的安排" : "待完成") {
                            ForEach(pending) { TaskRow(occurrence: $0, showDate: savedSelection != "today").tag($0.id) }
                        }
                    }
                    if !completed.isEmpty {
                        Section("已完成 · \(completed.count)") {
                            ForEach(completed) { TaskRow(occurrence: $0, showDate: savedSelection != "today").tag($0.id) }
                        }
                    }
                }
                .listStyle(.inset).scrollContentBackground(.hidden).padding(.horizontal, 14)
            }
            HStack(spacing: 8) {
                Circle().fill(model.cloudStatus == "iCloud 已同步" ? .green : .secondary.opacity(0.4)).frame(width: 5, height: 5)
                Text(model.isPreview ? "预览数据" : (model.activeSelection?.cloudEnabled == true
                     ? (model.cloudStatus.contains("重试") ? "iCloud 同步暂不可用 · 任务已保存在本机" : model.cloudStatus) : "任务保存在本机"))
                    .lineLimit(1).help(model.cloudStatus)
                Spacer()
                if model.canUndo { Button("撤销上一步") { Task { await model.undo() } }.buttonStyle(.plain).foregroundStyle(.blue) }
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.vertical, 12)
        }
    }
    private var trash: some View {
        VStack(alignment: .leading) {
            Text("已删除").font(.largeTitle.weight(.semibold)).padding(26)
            List {
                ForEach(model.snapshot.tasks.filter(\.isDeleted)) { task in
                    HStack {
                        Text(task.fields.title).foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复") { Task { _ = await model.run { try $0.setDeleted(id: task.id, deleted: false) } } }
                    }.padding(.vertical, 7)
                }
                ForEach(model.snapshot.overrides.filter(\.isDeleted)) { change in
                    HStack {
                        Text(change.fields?.title ?? model.snapshot.tasks.first { $0.id == change.taskID }?.fields.title ?? "重复任务")
                        Text(change.originalDay.rawValue).foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复") { Task { _ = await model.run { try $0.setDeleted(id: change.taskID, deleted: false, originalDay: change.originalDay) } } }
                    }
                }
            }.listStyle(.inset)
        }
    }
    private func addTask() {
        newTask = NewTaskDraft(fields: TaskFields(title: "", listID: selectedList?.id, day: savedSelection == "inbox" ? nil : .today()))
    }
    private func quickAdd() {
        guard !quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fields = TaskFields(title: quickTitle, listID: selectedList?.id, day: savedSelection == "inbox" ? nil : .today())
        Task {
            if await model.run({ try $0.createTask(fields: fields) }) != nil { quickTitle = ""; quickAddFocused = true }
        }
    }
    private func findOccurrence(_ id: String) -> TaskOccurrence? {
        let parts = id.split(separator: "/")
        guard parts.count == 2, let taskID = UUID(uuidString: String(parts[0])),
              let task = model.snapshot.tasks.first(where: { $0.id == taskID }) else { return nil }
        let original = LocalDay(rawValue: String(parts[1]))
        let change = model.snapshot.overrides.first { $0.taskID == taskID && $0.originalDay == original }
        var fields = change?.fields ?? task.fields
        if change?.fields == nil, let original { fields.day = original }
        return TaskOccurrence(taskID: taskID, originalDay: original, fields: fields,
                              completedAt: change?.completedAt ?? (original == nil ? task.completedAt : nil),
                              revision: change?.revision ?? task.revision, source: change?.source ?? task.source)
    }
}

private struct NewTaskDraft: Identifiable { let id = UUID(); var fields: TaskFields }
private struct ListSheet: Identifiable { let id = UUID(); var list: TodoList? }
