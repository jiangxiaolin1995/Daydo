import XCTest
@testable import DaydoCore

final class AppNavigationRequestTests: XCTestCase {
    func testWidgetTodayAndNewTaskLinks() throws {
        XCTAssertEqual(try XCTUnwrap(AppNavigationRequest(url: URL(string: "daydo://today")!)).destination, .today)
        XCTAssertEqual(try XCTUnwrap(AppNavigationRequest(url: URL(string: "daydo://new")!)).destination, .newTask)
    }

    func testTaskLinksPreserveTheSelectedOccurrence() throws {
        let id = UUID()
        let single = try XCTUnwrap(AppNavigationRequest(url: URL(string: "daydo://task/\(id)/single")!))
        let repeated = try XCTUnwrap(AppNavigationRequest(url: URL(string: "daydo://task/\(id)/2026-09-14")!))
        XCTAssertEqual(single.destination, .task("\(id.uuidString.lowercased())/single"))
        XCTAssertEqual(repeated.destination, .task("\(id.uuidString.lowercased())/2026-09-14"))
    }

    func testRepeatedClicksRemainSeparateNavigationRequests() throws {
        let url = URL(string: "daydo://task/\(UUID())/single")!
        let first = try XCTUnwrap(AppNavigationRequest(url: url))
        let second = try XCTUnwrap(AppNavigationRequest(url: url))
        XCTAssertEqual(first.destination, second.destination)
        XCTAssertNotEqual(first.id, second.id, "Reopening the same task after closing its inspector must still be delivered")
    }

    func testInvalidLinksDoNotNavigateOrCreateATask() {
        for raw in ["https://today", "daydo://unknown", "daydo://task/not-a-task/single",
                    "daydo://task/\(UUID())/2026-02-30", "daydo://today/unexpected"] {
            XCTAssertNil(AppNavigationRequest(url: URL(string: raw)!))
        }
    }
}
