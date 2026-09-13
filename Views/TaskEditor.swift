import SwiftUI
import DaydoCore

struct TaskEditor: View {
    @Environment(AppModel.self) private var model
    var occurrence: TaskOccurrence?
    var dismiss: () -> Void
    @State private var fields: TaskFields
    @State private var baseRevision: UUID?
    @State private var scope: EditScope = .occurrence
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    init(occurrence: TaskOccurrence?, initial: TaskFields, dismiss: @escaping () -> Void) {
        self.occurrence = occurrence; self.dismiss = dismiss
        _fields = State(initialValue: initial); _baseRevision = State(initialValue: occurrence?.revision)
    }
    private var hasDay: Binding<Bool> {
        Binding(get: { fields.day != nil }, set: {
            fields.day = $0 ? .today() : nil
            if !$0 { fields.startMinute = nil; fields.repeatRule = .init(); fields.reminderMinutesBefore = nil }
        })
    }
    private var date: Binding<Date> {
        Binding(get: { (fields.day ?? .today()).date() }, set: { fields.day = LocalDay($0) })
    }
    private var time: Binding<Date> {
        Binding(get: { (fields.day ?? .today()).date(minute: fields.startMinute ?? 9 * 60) },
                set: { fields.startMinute = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(occurrence == nil ? "新建任务" : "任务详情").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain).help("关闭详情")
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TextField("准备做些什么？", text: $fields.title, axis: .vertical)
                        .font(.system(size: 21, weight: .semibold)).textFieldStyle(.plain)
                        .lineLimit(2...5).focused($titleFocused).accessibilityIdentifier("task-title")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("备注").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $fields.notes).font(.system(size: 13)).scrollContentBackground(.hidden)
                            .frame(minHeight: 85).padding(7)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityIdentifier("task-notes")
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 17) {
                        Picker("清单", selection: $fields.listID) {
                            Text("收集箱").tag(nil as UUID?)
                            ForEach(model.snapshot.lists.filter { !$0.isArchived }) { list in Text(list.name).tag(Optional(list.id)) }
                        }
                        Toggle("计划日期", isOn: hasDay)
                        if fields.day != nil {
                            DatePicker("日期", selection: date, displayedComponents: .date)
                            Toggle("安排时间", isOn: Binding(get: { fields.startMinute != nil },
                                                             set: { fields.startMinute = $0 ? 9 * 60 : nil }))
                            if fields.startMinute != nil {
                                DatePicker("开始", selection: time, displayedComponents: .hourAndMinute)
                                Stepper("时长 \(fields.durationMinutes) 分钟", value: $fields.durationMinutes, in: 15...1440, step: 15)
                                Picker("时区", selection: $fields.timeZoneID) {
                                    ForEach(Array(Set([TimeZone.current.identifier, fields.timeZoneID, "Asia/Shanghai", "Asia/Tokyo",
                                                       "America/New_York", "America/Los_Angeles", "Europe/London", "UTC"])).sorted(), id: \.self) {
                                        Text($0).tag($0)
                                    }
                                }
                            }
                        }
                        Picker("优先级", selection: $fields.priority) {
                            ForEach(Priority.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        if fields.day != nil {
                            Picker("重复", selection: $fields.repeatRule.kind) {
                                ForEach(RepeatKind.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .onChange(of: fields.repeatRule.kind) { _, kind in
                                if kind == .weekly, fields.repeatRule.weekdays.isEmpty { fields.repeatRule.weekdays = [fields.day?.weekday ?? 2] }
                            }
                            if fields.repeatRule.kind == .weekly {
                                HStack(spacing: 5) {
                                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                                        let selected = fields.repeatRule.weekdays.contains(weekday)
                                        Button {
                                            if selected { fields.repeatRule.weekdays.removeAll { $0 == weekday } }
                                            else { fields.repeatRule.weekdays.append(weekday) }
                                        } label: {
                                            Text(["日", "一", "二", "三", "四", "五", "六"][weekday - 1])
                                                .font(.caption).frame(maxWidth: .infinity).padding(.vertical, 7)
                                                .background(selected ? Color.blue.opacity(0.15) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                                                .foregroundStyle(selected ? .blue : .secondary)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                            Picker("提醒", selection: $fields.reminderMinutesBefore) {
                                Text("不提醒").tag(nil as Int?)
                                Text("准时").tag(Optional(0))
                                Text("提前 5 分钟").tag(Optional(5))
                                Text("提前 15 分钟").tag(Optional(15))
                                Text("提前 30 分钟").tag(Optional(30))
                                Text("提前 1 小时").tag(Optional(60))
                                Text("提前 1 天").tag(Optional(1440))
                            }
                            if fields.reminderMinutesBefore != nil, fields.startMinute == nil {
                                DatePicker("提醒时间", selection: Binding(
                                    get: { (fields.day ?? .today()).date(minute: fields.allDayReminderMinute) },
                                    set: { fields.allDayReminderMinute = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }),
                                           displayedComponents: .hourAndMinute)
                            }
                        }
                    }.font(.system(size: 12))
                    if occurrence?.originalDay != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("修改范围").font(.caption).foregroundStyle(.secondary)
                            Picker("修改范围", selection: $scope) {
                                Text("仅这一次").tag(EditScope.occurrence)
                                Text("这次及以后").tag(EditScope.future)
                            }.labelsHidden().pickerStyle(.segmented)
                            Text("过去的任务记录会保留。").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if let occurrence {
                        Text("最近来源：\(occurrence.source == "app" ? "手动编辑" : occurrence.source)")
                            .font(.caption2).foregroundStyle(.tertiary)
                        if occurrence.revision != baseRevision {
                            Button("任务已更新，重新载入") { fields = occurrence.fields; baseRevision = occurrence.revision }
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }.padding(20)
            }
            Divider()
            HStack {
                if let occurrence {
                    Button(role: .destructive) { Task { await model.delete(occurrence); dismiss() } } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).help("删除任务")
                }
                Spacer()
                Button(occurrence == nil ? "创建任务" : "保存修改") { save() }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut("s")
                    .disabled(fields.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .accessibilityIdentifier("save-task")
            }.padding(18)
        }
        .task { if occurrence == nil { titleFocused = true } }
    }
    private func save() {
        isSaving = true
        let fields = fields, revision = baseRevision, scope = scope
        Task {
            if fields.reminderMinutesBefore != nil && !model.isPreview && !model.notificationPermission {
                await model.setReminderEnabled(true)
            }
            let result: TodoTask?
            if let occurrence, let revision {
                result = await model.run {
                    try $0.updateTask(id: occurrence.taskID, fields: fields, expectedRevision: revision,
                                      originalDay: occurrence.originalDay, scope: occurrence.originalDay == nil ? .task : scope)
                }
            } else { result = await model.run { try $0.createTask(fields: fields) } }
            isSaving = false
            if result != nil { dismiss() }
        }
    }
}
