import XCTest
@testable import DaydoCore

final class HistoryTests: XCTestCase {
    func testHistoryCursorConsumesExternalChangesOnceAndSurvivesReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaydoHistory-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("tasks.sqlite"), gate = TestAuthorization()
        let main = try TaskRepository(storeURL: url, authorization: gate)
        let agent = try TaskRepository(storeURL: url, authorization: gate)
        _ = try agent.createTask(fields: TaskFields(title: "从 Agent 创建"))
        XCTAssertGreaterThan(try main.consumeHistory(consumer: "test"), 0)
        XCTAssertEqual(try main.consumeHistory(consumer: "test"), 0)
        try main.close()
        let reopened = try TaskRepository(storeURL: url, authorization: gate)
        XCTAssertEqual(try reopened.consumeHistory(consumer: "test"), 0)
        _ = try agent.createTask(fields: TaskFields(title: "再次更新"))
        XCTAssertGreaterThan(try reopened.consumeHistory(consumer: "test"), 0)
        gate.setEnabled(false)
        XCTAssertThrowsError(try reopened.consumeHistory(consumer: "test"))
        try reopened.close(); try agent.close()
    }
}
