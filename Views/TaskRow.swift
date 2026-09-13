import SwiftUI
import DaydoCore

struct TaskRow: View {
    @Environment(AppModel.self) private var model
    var occurrence: TaskOccurrence
    var showDate = false
    private var list: TodoList? { model.snapshot.lists.first { $0.id == occurrence.fields.listID } }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { Task { await model.complete(occurrence) } } label: {
                Image(systemName: occurrence.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(occurrence.isCompleted ? .blue : DaydoStyle.priority(occurrence.fields.priority))
            }
            .buttonStyle(.borderless).help(occurrence.isCompleted ? "恢复未完成" : "完成任务")
            .accessibilityLabel((occurrence.isCompleted ? "恢复 " : "完成 ") + occurrence.fields.title)
            VStack(alignment: .leading, spacing: 6) {
                Text(occurrence.fields.title).font(.system(size: 14))
                    .strikethrough(occurrence.isCompleted).foregroundStyle(occurrence.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let list {
                        HStack(spacing: 4) {
                            Circle().fill(DaydoStyle.color(list.color)).frame(width: 5, height: 5)
                            Text(list.name)
                        }
                    }
                    if showDate, let day = occurrence.fields.day {
                        Text(day.rawValue).foregroundStyle(day < .today() && !occurrence.isCompleted ? .orange : .secondary)
                    }
                    if let minute = occurrence.fields.startMinute { Text(DaydoStyle.time(minute)) }
                    if occurrence.fields.repeatRule.kind != .never { Image(systemName: "repeat").accessibilityLabel("重复任务") }
                    if occurrence.fields.reminderMinutesBefore != nil { Image(systemName: "bell").accessibilityLabel("有提醒") }
                    if !occurrence.fields.notes.isEmpty { Image(systemName: "text.alignleft").accessibilityLabel("有备注") }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if occurrence.fields.priority != .none {
                Image(systemName: "flag.fill").font(.caption).foregroundStyle(DaydoStyle.priority(occurrence.fields.priority))
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            Button(occurrence.isCompleted ? "恢复未完成" : "完成任务") { Task { await model.complete(occurrence) } }
            Button("安排到今天") { Task { await model.move(occurrence, to: .today()) } }
            Button("安排到明天") { Task { await model.move(occurrence, to: .today().adding(days: 1)) } }
            Divider()
            Button("删除任务", role: .destructive) { Task { await model.delete(occurrence) } }
        }
        .draggable(occurrence.id)
    }
}
