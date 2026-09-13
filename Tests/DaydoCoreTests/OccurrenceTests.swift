import XCTest
@testable import DaydoCore

final class OccurrenceTests: XCTestCase {
    func testDateUsesCanonicalDecimalDigits() {
        XCTAssertNil(LocalDay(rawValue: "+026-01-01"))
    }
    func testMaximumSupportedDateHasOneOccurrence() {
        let last = LocalDay(rawValue: "9999-12-31")!
        let task = TodoTask(fields: TaskFields(title: "末日边界", day: last, repeatRule: .init(kind: .daily)))
        XCTAssertEqual(OccurrenceEngine.expand(.init(tasks: [task]), from: last, through: last).count, 1)
    }
    func day(_ value: String) -> LocalDay { LocalDay(rawValue: value)! }
    func task(_ kind: RepeatKind, start: String = "2026-09-11", weekdays: [Int] = []) -> TodoTask {
        TodoTask(fields: TaskFields(title: "阅读", day: day(start), repeatRule: .init(kind: kind, weekdays: weekdays)))
    }
    func testRejectsInvalidCalendarDates() {
        XCTAssertNil(LocalDay(rawValue: "2026-02-29"))
        XCTAssertNil(LocalDay(rawValue: "2026-13-01"))
        XCTAssertNotNil(LocalDay(rawValue: "2028-02-29"))
        XCTAssertEqual(day("2026-12-31").adding(days: 1), day("2027-01-01"))
    }
    func testWeekdaysSkipsWeekendAndDoesNotStartEarly() {
        let item = task(.weekdays)
        XCTAssertTrue(OccurrenceEngine.occurs(item, on: day("2026-09-11")))
        XCTAssertFalse(OccurrenceEngine.occurs(item, on: day("2026-09-12")))
        XCTAssertFalse(OccurrenceEngine.occurs(item, on: day("2026-09-13")))
        XCTAssertTrue(OccurrenceEngine.occurs(item, on: day("2026-09-14")))
        XCTAssertFalse(OccurrenceEngine.occurs(item, on: day("2026-09-10")))
    }
    func testCompletingAnOccurrenceDoesNotCompleteTomorrow() {
        let item = task(.daily)
        var completion = OccurrenceOverride(taskID: item.id, originalDay: day("2026-09-11"))
        completion.completedAt = Date()
        let result = OccurrenceEngine.expand(.init(tasks: [item], overrides: [completion]),
                                            from: day("2026-09-11"), through: day("2026-09-12"))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.isCompleted, true)
        XCTAssertEqual(result.last?.isCompleted, false)
        XCTAssertNotEqual(result.first?.id, result.last?.id)
    }
    func testMovedOccurrenceAppearsAtDestinationOutsideOriginalRange() {
        let item = task(.daily)
        var moved = OccurrenceOverride(taskID: item.id, originalDay: day("2026-09-11"))
        var fields = item.fields
        fields.day = day("2026-10-02")
        moved.fields = fields
        let snapshot = TaskSnapshot(tasks: [item], overrides: [moved])
        let old = OccurrenceEngine.expand(snapshot, from: day("2026-09-11"), through: day("2026-09-11"))
        let new = OccurrenceEngine.expand(snapshot, from: day("2026-10-02"), through: day("2026-10-02"))
        XCTAssertTrue(old.isEmpty)
        XCTAssertEqual(new.count, 2)
        XCTAssertTrue(new.contains { $0.originalDay == day("2026-09-11") })
    }
    func testWeeklyRuleAndEndDate() {
        var item = task(.weekly, start: "2026-09-07", weekdays: [2, 4])
        item.fields.repeatRule.until = day("2026-09-14")
        let result = OccurrenceEngine.expand(.init(tasks: [item]), from: day("2026-09-07"), through: day("2026-09-30"))
        XCTAssertEqual(result.compactMap(\.fields.day), [day("2026-09-07"), day("2026-09-09"), day("2026-09-14")])
    }
    func testTimeZoneAndDaylightSavingUseCalendarDays() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let date = day("2026-03-08").date(timeZone: zone, minute: 9 * 60)
        XCTAssertEqual(LocalDay(date, timeZone: zone), day("2026-03-08"))
        XCTAssertEqual(day("2026-03-08").adding(days: 1), day("2026-03-09"))
    }
    func testArchivedListsAndDeletedTasksAreExcluded() {
        var list = TodoList(name: "旧清单")
        list.isArchived = true
        var item = task(.daily)
        item.fields.listID = list.id
        let snapshot = TaskSnapshot(lists: [list], tasks: [item])
        XCTAssertTrue(OccurrenceEngine.expand(snapshot, from: day("2026-09-11"), through: day("2026-09-11")).isEmpty)
    }
}
