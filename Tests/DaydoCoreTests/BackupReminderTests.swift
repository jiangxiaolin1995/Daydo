import XCTest
@testable import DaydoCore

final class BackupReminderTests: XCTestCase {
    func day(_ value: String) -> LocalDay { LocalDay(rawValue: value)! }
    func testReminderUsesTaskTimeZoneAndDropsCompletedOccurrences() {
        let date = day("2026-09-13")
        let task = TodoTask(fields: TaskFields(title: "会议", day: date, startMinute: 10 * 60,
                                             timeZoneID: "Asia/Shanghai", repeatRule: .init(kind: .daily),
                                             reminderMinutesBefore: 15))
        var done = OccurrenceOverride(taskID: task.id, originalDay: date)
        done.completedAt = Date()
        let now = date.date(timeZone: TimeZone(identifier: "Asia/Shanghai")!, minute: 9 * 60)
        let planned = ReminderPlanner.plan(.init(tasks: [task]), now: now, limit: 2)
        XCTAssertEqual(planned.count, 2)
        XCTAssertEqual(planned.first?.fireDate, date.date(timeZone: TimeZone(identifier: "Asia/Shanghai")!, minute: 585))
        let after = ReminderPlanner.plan(.init(tasks: [task], overrides: [done]), now: now, limit: 2)
        XCTAssertEqual(after.first?.originalDay, date.adding(days: 1))
    }
    func testBackupRoundTripDeduplicatesAndDoesNotOverwriteExistingEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaydoBackup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = TestAuthorization()
        let source = try TaskRepository(storeURL: directory.appendingPathComponent("source.sqlite"), authorization: gate)
        let list = try source.createList(name: "工作")
        _ = try source.createTask(fields: TaskFields(title: "原始标题", listID: list.id))
        let data = try source.exportBackup()
        let target = try TaskRepository(storeURL: directory.appendingPathComponent("target.sqlite"), authorization: gate)
        let preview = try target.previewImport(data)
        XCTAssertEqual(preview.newTasks, 1)
        XCTAssertEqual(preview.newLists, 1)
        try target.importBackup(data)
        let current = try target.snapshot().tasks[0]
        var fields = current.fields
        fields.title = "本机已修改"
        _ = try target.updateTask(id: current.id, fields: fields, expectedRevision: current.revision)
        let repeated = try target.importBackup(data)
        XCTAssertEqual(repeated.newTasks, 0)
        XCTAssertEqual(try target.snapshot().tasks[0].fields.title, "本机已修改")
    }
    func testUnknownBackupSchemaIsRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaydoBackup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try TaskRepository(storeURL: directory.appendingPathComponent("tasks.sqlite"), authorization: TestAuthorization())
        let data = Data(#"{"schemaVersion":999,"exportedAt":"2026-09-13T00:00:00Z","snapshot":{"lists":[],"tasks":[],"overrides":[]}}"#.utf8)
        XCTAssertThrowsError(try target.importBackup(data))
    }

    func testImportRejectsOccurrenceWithMissingList() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaydoBackup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try TaskRepository(storeURL: directory.appendingPathComponent("tasks.sqlite"), authorization: TestAuthorization())
        defer { try? target.close() }
        let task = TodoTask(fields: TaskFields(title: "每天阅读", day: day("2026-09-13"), repeatRule: .init(kind: .daily)))
        var change = OccurrenceOverride(taskID: task.id, originalDay: day("2026-09-13"))
        var fields = task.fields
        fields.listID = UUID()
        change.fields = fields
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(BackupEnvelope(snapshot: .init(tasks: [task], overrides: [change])))
        XCTAssertThrowsError(try target.previewImport(data))
        XCTAssertThrowsError(try target.importBackup(data))
        XCTAssertTrue(try target.snapshot().tasks.isEmpty)
    }
}
