import SwiftUI
import DaydoCore

private enum CalendarMode: String, CaseIterable { case day = "日", week = "周", month = "月" }

struct CalendarView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedID: String?
    var query = ""
    var onCreate: (LocalDay, Int?) -> Void
    var onSelect: (TaskOccurrence) -> Void
    @State private var mode: CalendarMode = .week
    @State private var focus = LocalDay.today()
    private let hourHeight: CGFloat = 58
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = 2; value.timeZone = .current
        return value
    }
    private var days: [LocalDay] {
        if mode == .day { return [focus] }
        if mode == .week {
            let first = focus.adding(days: -((focus.weekday + 5) % 7))
            return (0..<7).map { first.adding(days: $0) }
        }
        let firstOfMonth = LocalDay(calendar.date(from: calendar.dateComponents([.year, .month], from: focus.date()))!)
        let first = firstOfMonth.adding(days: -((firstOfMonth.weekday + 5) % 7))
        return (0..<42).map { first.adding(days: $0) }
    }
    private var items: [TaskOccurrence] {
        let all = OccurrenceEngine.expand(model.snapshot, from: days.first!.adding(days: -1), through: days.last!.adding(days: 1))
        return query.isEmpty ? all : all.filter { $0.fields.title.localizedCaseInsensitiveContains(query) || $0.fields.notes.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(focus.date(), format: .dateTime.year().month(.wide)).font(.system(size: 25, weight: .semibold))
                    Text(mode == .month ? "为重要的事情，留出时间。" : "让每一件事，都有自己的时间。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.help("上一\(mode.rawValue)")
                    Button("今天") { focus = .today() }
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.help("下一\(mode.rawValue)")
                }.buttonStyle(.borderless).font(.system(size: 12))
                Picker("日历视图", selection: $mode) {
                    ForEach(CalendarMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 123).accessibilityIdentifier("calendar-mode")
            }.padding(.horizontal, 25).padding(.vertical, 24)
            Divider()
            if mode == .month { monthGrid }
            else { timeline }
        }
    }
    private var monthGrid: some View {
        GeometryReader { geometry in
          ScrollView(.vertical) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(["周一", "周二", "周三", "周四", "周五", "周六", "周日"], id: \.self) { day in
                        Text(day).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        monthCell(day, height: max(86, (geometry.size.height - 40) / 6))
                    }
                }
            }
          }
        }
    }
    private func monthCell(_ day: LocalDay, height: CGFloat) -> some View {
        let currentMonth = calendar.component(.month, from: day.date()) == calendar.component(.month, from: focus.date())
        let entries = items.filter { $0.fields.day == day }
        let visibleCount = min(3, max(1, Int((height - 50) / 19)))
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Button { focus = day; mode = .day } label: {
                    Text("\(calendar.component(.day, from: day.date()))")
                        .font(.system(size: 12, weight: day == .today() ? .semibold : .regular))
                        .frame(width: 25, height: 25)
                        .foregroundStyle(day == .today() ? Color.white : currentMonth ? Color.primary : Color.secondary.opacity(0.5))
                        .background(day == .today() ? Color.blue : .clear, in: Circle())
                }.buttonStyle(.plain)
                Spacer()
            }.padding(.horizontal, 5).padding(.top, 5)
            ForEach(Array(entries.prefix(visibleCount))) { occurrence in
                HStack(spacing: 4) {
                    if occurrence.isCompleted { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                    Text(occurrence.fields.title).lineLimit(1).strikethrough(occurrence.isCompleted)
                }
                .font(.system(size: 10)).foregroundStyle(eventColor(occurrence))
                .padding(.horizontal, 5).padding(.vertical, 2).frame(maxWidth: .infinity, alignment: .leading)
                .background(eventColor(occurrence).opacity(occurrence.isCompleted ? 0.04 : 0.09), in: RoundedRectangle(cornerRadius: 4))
                .padding(.horizontal, 4).contentShape(Rectangle())
                .onTapGesture { selectedID = occurrence.id; onSelect(occurrence) }
                .draggable(occurrence.id)
            }
            if entries.count > visibleCount {
                Button("还有 \(entries.count - visibleCount) 项") { focus = day; mode = .day }
                    .buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.secondary).padding(.leading, 8)
            }
            Spacer(minLength: 0)
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(currentMonth ? Color.clear : .secondary.opacity(0.025))
        .overlay(alignment: .bottom) { Rectangle().fill(.separator.opacity(0.55)).frame(height: 0.5) }
        .overlay(alignment: .trailing) { Rectangle().fill(.separator.opacity(0.55)).frame(width: 0.5) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onCreate(day, nil) }
        .dropDestination(for: String.self) { values, _ in drop(values, day: day, minute: nil) }
    }
    private var timeline: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(width: 47)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 5) {
                        Text(day.date(), format: .dateTime.weekday(.abbreviated)).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text("\(calendar.component(.day, from: day.date()))")
                            .font(.system(size: 20, weight: day == .today() ? .semibold : .regular))
                            .foregroundStyle(day == .today() ? .blue : .primary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(day == .today() ? .blue.opacity(0.035) : .clear)
                    .contentShape(Rectangle()).onTapGesture { focus = day; mode = .day }
                }
            }
            ScrollView(.vertical) {
              HStack(alignment: .top, spacing: 0) {
                Text("全天").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 47).padding(.top, 8)
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 4) {
                        ForEach(items.filter { $0.fields.day == day && $0.fields.startMinute == nil }) { occurrence in
                            Text(occurrence.fields.title).font(.system(size: 10)).lineLimit(1)
                                .strikethrough(occurrence.isCompleted)
                                .padding(5).frame(maxWidth: .infinity, alignment: .leading)
                                .background(eventColor(occurrence).opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(eventColor(occurrence)).onTapGesture { selectedID = occurrence.id; onSelect(occurrence) }
                                .draggable(occurrence.id)
                        }
                    }
                    .padding(4).frame(maxWidth: .infinity, minHeight: 35)
                    .contentShape(Rectangle()).onTapGesture(count: 2) { onCreate(day, nil) }
                    .dropDestination(for: String.self) { values, _ in drop(values, day: day, minute: nil, clearTime: true) }
                }
              }
            }
            .frame(height: CGFloat(min(132, max(35, (days.map { day in items.filter { $0.fields.day == day && $0.fields.startMinute == nil }.count }.max() ?? 0) * 28 + 8))))
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(0..<24) { hour in
                                Text(String(format: "%02d:00", hour)).font(.system(size: 9)).monospacedDigit().foregroundStyle(.tertiary)
                                    .frame(width: 47, height: hourHeight, alignment: .top).id("hour-\(hour)")
                            }
                        }
                        ForEach(days, id: \.self) { day in dayColumn(day) }
                    }.padding(.top, 8)
                }
                .onAppear { proxy.scrollTo("hour-8", anchor: .top) }
            }
        }
    }
    private func dayColumn(_ day: LocalDay) -> some View {
        GeometryReader { geometry in
            let segments = CalendarEventLayout.layout(items, on: day)
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<24) { _ in
                        VStack(spacing: 0) {
                            Rectangle().fill(.separator.opacity(0.55)).frame(height: 0.5)
                            Spacer()
                            Rectangle().fill(.separator.opacity(0.2)).frame(height: 0.5)
                            Spacer()
                        }.frame(height: hourHeight)
                    }
                }
                ForEach(segments) { segment in
                    let width = max(22, (geometry.size.width - 6) / CGFloat(segment.columns) - 3)
                    CalendarEventView(segment: segment, color: eventColor(segment.occurrence), hourHeight: hourHeight,
                                      selected: selectedID == segment.occurrence.id,
                                      onSelect: { selectedID = segment.occurrence.id; onSelect(segment.occurrence) },
                                      onResize: { duration in
                        Task { await model.move(segment.occurrence, to: segment.occurrence.fields.day ?? day, duration: duration) }
                    })
                    .frame(width: width)
                    .offset(x: 3 + CGFloat(segment.column) * (width + 3), y: CGFloat(segment.start) * hourHeight / 60)
                }
                if day == .today() {
                    let minute = calendar.component(.hour, from: model.lastRefresh) * 60 + calendar.component(.minute, from: model.lastRefresh)
                    HStack(spacing: 0) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Rectangle().fill(.red.opacity(0.6)).frame(height: 1)
                    }.offset(y: CGFloat(minute) * hourHeight / 60).allowsHitTesting(false)
                }
            }
            .frame(height: hourHeight * 24)
            .background(day == .today() ? .blue.opacity(0.018) : .clear)
            .overlay(alignment: .leading) { Rectangle().fill(.separator.opacity(0.4)).frame(width: 0.5) }
            .contentShape(Rectangle())
            .onTapGesture(count: 2, coordinateSpace: .local) { point in onCreate(day, snappedMinute(point.y)) }
            .dropDestination(for: String.self) { values, location in drop(values, day: day, minute: snappedMinute(location.y)) }
        }
        .frame(maxWidth: .infinity).frame(height: hourHeight * 24)
    }
    private func snappedMinute(_ y: CGFloat) -> Int { min(1425, max(0, Int((y / hourHeight * 60 / 15).rounded()) * 15)) }
    private func eventColor(_ task: TaskOccurrence) -> Color {
        DaydoStyle.color(model.snapshot.lists.first { $0.id == task.fields.listID }?.color ?? "#2563EB")
    }
    private func shift(_ direction: Int) {
        if mode == .month { focus = LocalDay(calendar.date(byAdding: .month, value: direction, to: focus.date())!) }
        else { focus = focus.adding(days: direction * (mode == .week ? 7 : 1)) }
    }
    private func drop(_ values: [String], day: LocalDay, minute: Int?, clearTime: Bool = false) -> Bool {
        guard let id = values.first, let occurrence = items.first(where: { $0.id == id }) else { return false }
        Task {
            if clearTime {
                var fields = occurrence.fields; fields.day = day; fields.startMinute = nil
                let updated = fields
                _ = await model.run { try $0.updateTask(id: occurrence.taskID, fields: updated, expectedRevision: occurrence.revision,
                                                      originalDay: occurrence.originalDay, scope: occurrence.originalDay == nil ? .task : .occurrence) }
            } else { await model.move(occurrence, to: day, minute: minute) }
        }
        return true
    }
}

private struct CalendarEventView: View {
    var segment: CalendarSegment
    var color: Color
    var hourHeight: CGFloat
    var selected: Bool
    var onSelect: () -> Void
    var onResize: (Int) -> Void
    @State private var resizeDelta: CGFloat = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(segment.occurrence.fields.title).font(.system(size: 11, weight: .medium)).lineLimit(2)
                .strikethrough(segment.occurrence.isCompleted)
            if segment.end - segment.start >= 45 {
                Text(DaydoStyle.time(segment.start) + " – " + DaydoStyle.time(segment.end))
                    .font(.system(size: 9)).monospacedDigit().opacity(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.top, 6).padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: max(24, CGFloat(segment.end - segment.start) * hourHeight / 60 - 2 + resizeDelta))
        .foregroundStyle(segment.occurrence.isCompleted ? .secondary : color)
        .background(color.opacity(selected ? 0.19 : 0.1), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.7)).frame(width: 2).padding(.vertical, 4) }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? color.opacity(0.65) : .clear, lineWidth: 1))
        .contentShape(Rectangle()).onTapGesture(perform: onSelect).draggable(segment.occurrence.id)
        .overlay(alignment: .bottom) {
            Capsule().fill(color.opacity(0.5)).frame(width: 18, height: 3).padding(.vertical, 4)
                .contentShape(Rectangle()).help("拖动调整时长")
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { resizeDelta = $0.translation.height }
                    .onEnded {
                        let change = Int(($0.translation.height / hourHeight * 60 / 15).rounded()) * 15
                        resizeDelta = 0
                        onResize(min(1440, max(15, segment.occurrence.fields.durationMinutes + change)))
                    })
        }
    }
}

private struct CalendarSegment: Identifiable {
    var occurrence: TaskOccurrence
    var start: Int
    var end: Int
    var column = 0
    var columns = 1
    var id: String { occurrence.id }
}

private enum CalendarEventLayout {
    static func layout(_ items: [TaskOccurrence], on day: LocalDay) -> [CalendarSegment] {
        let segments = items.compactMap { item -> CalendarSegment? in
            guard let minute = item.fields.startMinute, let plannedDay = item.fields.day else { return nil }
            if plannedDay == day { return CalendarSegment(occurrence: item, start: minute, end: min(1440, minute + item.fields.durationMinutes)) }
            if plannedDay.adding(days: 1) == day, minute + item.fields.durationMinutes > 1440 {
                return CalendarSegment(occurrence: item, start: 0, end: minute + item.fields.durationMinutes - 1440)
            }
            return nil
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        var result: [CalendarSegment] = [], cluster: [CalendarSegment] = []
        var clusterEnd = 0
        for segment in segments {
            if !cluster.isEmpty && segment.start >= clusterEnd { result += arrange(cluster); cluster = []; clusterEnd = 0 }
            cluster.append(segment); clusterEnd = max(clusterEnd, segment.end)
        }
        result += arrange(cluster)
        return result
    }
    private static func arrange(_ cluster: [CalendarSegment]) -> [CalendarSegment] {
        var laneEnds: [Int] = []
        var result: [CalendarSegment] = []
        for var segment in cluster {
            let index = laneEnds.firstIndex { $0 <= segment.start } ?? laneEnds.count
            if index == laneEnds.count { laneEnds.append(segment.end) } else { laneEnds[index] = segment.end }
            segment.column = index; result.append(segment)
        }
        return result.map { var value = $0; value.columns = max(1, laneEnds.count); return value }
    }
}
