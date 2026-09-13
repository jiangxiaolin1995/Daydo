import WidgetKit
import SwiftUI
import DaydoCore

struct TodayEntry: TimelineEntry {
    var date: Date
    var tasks: [TaskOccurrence]
    var completed: Int
    var errorMessage: String?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), tasks: [], completed: 0, errorMessage: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        Task { completion(await read()) }
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayEntry>) -> Void) {
        Task {
            let entry = await read()
            let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
            let next = min(Date().addingTimeInterval(15 * 60), midnight)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
    private func read() async -> TodayEntry {
        do {
            if let selected = try SharedEnvironment.selection(), selected.cloudEnabled {
                let account = await CloudAccountService.resolve(previous: selected, allowCached: true)
                guard account.selection == selected else {
                    try SharedEnvironment.setAccessLocked(true)
                    return TodayEntry(date: Date(), tasks: [], completed: 0,
                                      errorMessage: "系统 iCloud 账户已变化，请打开 Daydo。")
                }
            }
            let repository = try SharedEnvironment.repository()
            defer { try? repository.close() }
            let today = LocalDay.today()
            let tasks = OccurrenceEngine.expand(try repository.snapshot(), from: today, through: today)
            return TodayEntry(date: Date(), tasks: tasks.filter { !$0.isCompleted }, completed: tasks.filter(\.isCompleted).count,
                              errorMessage: nil)
        } catch {
            return TodayEntry(date: Date(), tasks: [], completed: 0, errorMessage: error.localizedDescription)
        }
    }
}

struct TodayWidgetView: View {
    var entry: TodayEntry
    @Environment(\.widgetFamily) private var family
    var capacity: Int { family == .systemSmall ? 2 : family == .systemMedium ? 3 : 7 }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今天").font(.headline)
                Spacer()
                Text(entry.date, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
            }
            if entry.errorMessage != nil {
                Link(destination: URL(string: "daydo://today")!) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle").font(.title2).foregroundStyle(.blue)
                        Text("暂时无法读取任务").font(.subheadline)
                        Text("打开 Daydo 检查").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if entry.tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.blue)
                    Text(entry.completed > 0 ? "今天的任务都完成了" : "今天，留一点从容").font(.subheadline)
                    Link("添加任务", destination: URL(string: "daydo://new")!).font(.caption)
                }
            } else {
                ForEach(Array(entry.tasks.prefix(capacity))) { task in
                    HStack(spacing: 8) {
                        Button(intent: CompleteTaskIntent(taskID: task.taskID.uuidString, occurrenceDay: task.originalDay?.rawValue ?? "")) {
                            Image(systemName: "circle").font(.system(size: 19)).foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("完成 \(task.fields.title)")
                        Link(destination: URL(string: "daydo://task/\(task.id)")!) {
                            Text(task.fields.title).font(.subheadline).lineLimit(1).foregroundStyle(.primary)
                        }
                        Spacer(minLength: 0)
                        if let minute = task.fields.startMinute, family != .systemSmall {
                            Text(String(format: "%02d:%02d", minute / 60, minute % 60)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                if entry.tasks.count > capacity {
                    Link("还有 \(entry.tasks.count - capacity) 项", destination: URL(string: "daydo://today")!).font(.caption2)
                } else {
                    Text("DAYDO").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.8).foregroundStyle(.blue)
                }
                Spacer()
                if entry.errorMessage == nil {
                    Text("\(entry.completed)/\(entry.completed + entry.tasks.count)").font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel("已完成 \(entry.completed) 项，共 \(entry.completed + entry.tasks.count) 项")
                }
            }
        }
        .containerBackground(for: .widget) { Color(.windowBackgroundColor) }
        .widgetURL(URL(string: "daydo://today"))
        .privacySensitive()
    }
}

@main
struct DaydoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: DaydoConstants.widgetKind, provider: TodayProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("今天的待办")
            .description("查看今天的安排，直接勾选完成。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
