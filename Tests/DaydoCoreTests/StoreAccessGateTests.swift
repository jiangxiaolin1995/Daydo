import XCTest
@testable import DaydoCore

final class StoreAccessGateTests: XCTestCase {
    func testStartupChecksTheSystemAccountBeforeOpeningACachedCloudStore() async {
        let old = StoreSelection(namespace: "icloud-old", cloudEnabled: true)
        let current = StoreSelection(namespace: "icloud-new", cloudEnabled: true)
        let resolved = await StoreSelection.forStartup(previous: old, accessLocked: false,
                                                       local: .init(namespace: "local", cloudEnabled: false)) { _, _ in current }
        XCTAssertEqual(resolved, current)
        XCTAssertThrowsError(try StoreAccessGate(namespace: old.namespace, state: { (resolved, false) }).requireAuthorization())
    }

    func testFirstLaunchCanOpenLocalTasksWithoutWaitingForCloud() async {
        let local = StoreSelection(namespace: "local", cloudEnabled: false)
        let resolved = await StoreSelection.forStartup(previous: nil, accessLocked: false, local: local) { _, _ in
            XCTFail("A new local store must not require a network account lookup")
            return .init(namespace: "icloud", cloudEnabled: true)
        }
        XCTAssertEqual(resolved, local)
    }

    func testStartupAfterAnAccountChangeDoesNotAllowCachedIdentity() async {
        let old = StoreSelection(namespace: "icloud-old", cloudEnabled: true)
        let local = StoreSelection(namespace: "local", cloudEnabled: false)
        let resolved = await StoreSelection.forStartup(previous: old, accessLocked: true, local: local) { _, allowCached in
            XCTAssertFalse(allowCached)
            return local
        }
        XCTAssertEqual(resolved, local)
    }

    func testLocalTasksWorkWithoutAnAppleSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DaydoGuest-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let selected = StoreSelection(namespace: "local-test", cloudEnabled: false)
        let gate = StoreAccessGate(namespace: selected.namespace, state: { (selected, false) })
        let repository = try TaskRepository(storeURL: directory.appendingPathComponent("Daydo.sqlite"), authorization: gate)
        defer { try? repository.close() }
        let task = try repository.createTask(fields: TaskFields(title: "免登录创建"))
        try repository.setCompletion(id: task.id, completed: true)
        XCTAssertNotNil(try repository.snapshot().tasks.first?.completedAt)
    }

    func testAccountSwitchRefusesThePreviousStore() {
        let current = StoreSelection(namespace: "icloud-new", cloudEnabled: true)
        let gate = StoreAccessGate(namespace: "icloud-old", state: { (current, false) })
        XCTAssertThrowsError(try gate.requireAuthorization())
    }

    func testSwitchInProgressAndUninitializedStoreRefuseAccess() {
        let current = StoreSelection(namespace: "local-test", cloudEnabled: false)
        XCTAssertThrowsError(try StoreAccessGate(namespace: current.namespace, state: { (current, true) }).requireAuthorization())
        XCTAssertThrowsError(try StoreAccessGate(namespace: current.namespace, state: { (nil, false) }).requireAuthorization())
    }
}
