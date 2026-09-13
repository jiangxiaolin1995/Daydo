import Foundation
import XCTest
@testable import DaydoCore

final class TestAuthorization: AuthorizationChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    func setEnabled(_ value: Bool) { lock.lock(); defer { lock.unlock() }; enabled = value }
    func requireAuthorization() throws {
        lock.lock(); defer { lock.unlock() }
        if !enabled { throw DaydoError.authenticationRequired }
    }
}

final class RepositoryTests: XCTestCase {
    var directory: URL!
    var gate: TestAuthorization!
    var repository: TaskRepository!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaydoTests-\(UUID())")
        gate = TestAuthorization()
        repository = try TaskRepository(storeURL: directory.appendingPathComponent("tasks.sqlite"), authorization: gate)
    }
    override func tearDownWithError() throws {
        repository = nil
        try? FileManager.default.removeItem(at: directory)
    }
    func day(_ text: String) -> LocalDay { LocalDay(rawValue: text)! }
    func testCreateIsIdempotentAndRejectsDifferentPayloadForSameRequest() throws {
        let fields = TaskFields(title: "发周报", day: day("2026-09-13"))
        let first = try repository.createTask(fields: fields, requestID: "create-1")
        let second = try repository.createTask(fields: fields, requestID: "create-1")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try repository.snapshot().tasks.count, 1)
        XCTAssertThrowsError(try repository.createTask(fields: TaskFields(title: "另一个任务"), requestID: "create-1"))
    }
    func testEveryReadAndWriteChecksAuthentication() throws {
        let task = try repository.createTask(fields: TaskFields(title: "私人任务"))
        gate.setEnabled(false)
        for action in [
            { _ = try self.repository.snapshot() },
            { _ = try self.repository.createTask(fields: TaskFields(title: "禁止")) },
            { try self.repository.setCompletion(id: task.id, completed: true) }
        ] {
            XCTAssertThrowsError(try action()) { XCTAssertEqual($0 as? DaydoError, .authenticationRequired) }
        }
    }
    func testVersionConflictAcrossTwoRepositoryInstances() throws {
        let task = try repository.createTask(fields: TaskFields(title: "初稿"))
        let second = try TaskRepository(storeURL: directory.appendingPathComponent("tasks.sqlite"), authorization: gate)
        var fields = task.fields
        fields.title = "新稿"
        _ = try repository.updateTask(id: task.id, fields: fields, expectedRevision: task.revision)
        XCTAssertThrowsError(try second.updateTask(id: task.id, fields: task.fields, expectedRevision: task.revision)) {
            XCTAssertEqual($0 as? DaydoError, .conflict)
        }
        XCTAssertEqual(try second.snapshot().tasks.first?.fields.title, "新稿")
    }
    func testFutureEditPreservesCompletedHistory() throws {
        let task = try repository.createTask(fields: TaskFields(title: "阅读", day: day("2026-09-11"),
                                                               repeatRule: .init(kind: .daily)))
        try repository.setCompletion(id: task.id, completed: true, originalDay: day("2026-09-11"))
        var fields = task.fields
        fields.title = "读书并记笔记"
        fields.day = day("2026-09-13")
        _ = try repository.updateTask(id: task.id, fields: fields, expectedRevision: task.revision,
                                     originalDay: day("2026-09-13"), scope: .future)
        let snapshot = try repository.snapshot()
        let result = OccurrenceEngine.expand(snapshot, from: day("2026-09-11"), through: day("2026-09-14"))
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0].fields.title, "阅读")
        XCTAssertTrue(result[0].isCompleted)
        XCTAssertEqual(result[1].fields.title, "阅读")
        XCTAssertEqual(result[2].fields.title, "读书并记笔记")
        XCTAssertEqual(result[3].fields.title, "读书并记笔记")
    }
    func testCompletionIsIdempotentAndCanBeReopened() throws {
        let task = try repository.createTask(fields: TaskFields(title: "完成测试"))
        try repository.setCompletion(id: task.id, completed: true)
        let first = try repository.snapshot().tasks[0]
        try repository.setCompletion(id: task.id, completed: true)
        XCTAssertEqual(try repository.snapshot().tasks[0].completedAt, first.completedAt)
        try repository.setCompletion(id: task.id, completed: false)
        XCTAssertNil(try repository.snapshot().tasks[0].completedAt)
    }
    func testSoftDeleteAndUndoRestoreData() throws {
        let task = try repository.createTask(fields: TaskFields(title: "保留备注", notes: "不可丢失"))
        try repository.setDeleted(id: task.id, deleted: true)
        XCTAssertTrue(try repository.snapshot().tasks[0].isDeleted)
        try repository.setDeleted(id: task.id, deleted: false)
        XCTAssertFalse(try repository.snapshot().tasks[0].isDeleted)
        XCTAssertEqual(try repository.snapshot().tasks[0].fields.notes, "不可丢失")
    }
    func testRepeatedTaskRequiresAnOccurrenceToComplete() throws {
        let task = try repository.createTask(fields: TaskFields(title: "每天", day: day("2026-09-11"),
                                                               repeatRule: .init(kind: .daily)))
        XCTAssertThrowsError(try repository.setCompletion(id: task.id, completed: true))
        XCTAssertThrowsError(try repository.setCompletion(id: task.id, completed: true, originalDay: day("2026-09-10")))
    }
    func testConcurrentRequestsAcrossConnectionsCreateOneTask() throws {
        let first = repository!
        let second = try TaskRepository(storeURL: directory.appendingPathComponent("tasks.sqlite"), authorization: gate)
        defer { try? second.close() }
        let results = ConcurrentResults()
        DispatchQueue.concurrentPerform(iterations: 16) { index in
            do {
                let task = try (index.isMultiple(of: 2) ? first : second)
                    .createTask(fields: TaskFields(title: "相同请求"), requestID: "concurrent-1")
                results.append(task.id)
            } catch { results.fail() }
        }
        XCTAssertEqual(results.failures, 0)
        XCTAssertEqual(Set(results.ids).count, 1)
        XCTAssertEqual(try repository.snapshot().tasks.count, 1)
    }
}

private final class ConcurrentResults: @unchecked Sendable {
    let lock = NSLock()
    var ids: [UUID] = []
    var failures = 0
    func append(_ id: UUID) { lock.lock(); defer { lock.unlock() }; ids.append(id) }
    func fail() { lock.lock(); defer { lock.unlock() }; failures += 1 }
}
