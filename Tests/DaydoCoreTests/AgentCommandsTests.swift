import XCTest
@testable import DaydoCore

final class AgentCommandsTests: XCTestCase {
    var directory: URL!
    var repository: TaskRepository!
    var gate: TestAuthorization!
    var commands: AgentCommands!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaydoAgentTests-\(UUID())")
        gate = TestAuthorization()
        repository = try TaskRepository(storeURL: directory.appendingPathComponent("store.sqlite"), authorization: gate)
        commands = AgentCommands(repository: repository)
    }
    override func tearDownWithError() throws {
        try repository.close(); commands = nil; repository = nil
        try FileManager.default.removeItem(at: directory)
    }
    func call(_ name: String, _ args: [String: Any]) throws -> [String: Any] {
        let data = try commands.handle(name, arguments: JSONSerialization.data(withJSONObject: args), source: "mcp:test")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func testAgentCreatePatchCompleteAndIdempotency() throws {
        let args: [String: Any] = ["fields": ["title": "Agent 新增", "day": "2026-12-31", "timeZoneID": "Asia/Shanghai"], "requestId": "agent-1"]
        let task = try call("create_task", args)
        XCTAssertEqual(try call("create_task", args)["id"] as? String, task["id"] as? String)
        let update = try call("update_task", ["taskId": task["id"]!, "expectedRevision": task["revision"]!,
                                              "fields": ["title": "编辑完成", "day": NSNull()]])
        let fields = try XCTUnwrap(update["fields"] as? [String: Any])
        XCTAssertEqual(fields["title"] as? String, "编辑完成")
        XCTAssertNil(fields["day"])
        _ = try call("set_task_completion", ["taskId": task["id"]!, "completed": true])
        _ = try call("set_task_completion", ["taskId": task["id"]!, "completed": true])
        XCTAssertNotNil(try repository.snapshot().tasks[0].completedAt)
        XCTAssertEqual(try repository.snapshot().tasks[0].source, "mcp:test")
    }
    func testStrictInputsDoNotCoerceDatesBooleansOrUnknownFields() throws {
        XCTAssertThrowsError(try call("create_task", ["fields": ["title": "无效", "day": "2026-02-30"]]))
        XCTAssertThrowsError(try call("create_task", ["fields": ["title": "无效", "surprise": true]]))
        let task = try repository.createTask(fields: TaskFields(title: "原始"))
        XCTAssertThrowsError(try call("set_task_completion", ["taskId": task.id.uuidString, "completed": "false"]))
        XCTAssertThrowsError(try call("list_tasks", ["from": "2026-01-01", "through": "2028-01-01"]))
        XCTAssertFalse(try repository.snapshot().tasks[0].completedAt != nil)
    }
    func testLockedAgentCannotReadOrMutate() throws {
        gate.setEnabled(false)
        XCTAssertThrowsError(try call("list_lists", [:])) { XCTAssertEqual($0 as? DaydoError, .authenticationRequired) }
        XCTAssertThrowsError(try call("create_task", ["fields": ["title": "禁止"]])) { XCTAssertEqual($0 as? DaydoError, .authenticationRequired) }
    }
    func testRepeatInstanceQueryAndExplicitCompletion() throws {
        let task = try call("create_task", ["fields": ["title": "每日", "day": "2026-12-31", "repeatRule": ["kind": "daily"]]])
        XCTAssertThrowsError(try call("set_task_completion", ["taskId": task["id"]!, "completed": true]))
        _ = try call("set_task_completion", ["taskId": task["id"]!, "occurrenceDay": "2027-01-01", "completed": true])
        let result = try call("list_tasks", ["from": "2026-12-31", "through": "2027-01-02", "completed": true])
        XCTAssertEqual((result["items"] as? [[String: Any]])?.count, 1)
    }
}
