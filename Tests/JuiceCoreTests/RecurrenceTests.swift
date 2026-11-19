import XCTest
@testable import JuiceCore

// Mirrors the website's src/utils/taskRecurrence.test.ts.
final class RecurrenceTests: XCTestCase {
    let weekly = JuiceTask(id: "task-1", title: "Water plants", dueDate: day("2026-03-10"),
                           recurrence: .weekly, createdAt: "2026-03-01T12:00:00.000Z")

    func testNextUsesCalendarDates() {
        XCTAssertEqual(RecurrenceRules.next(day("2026-03-10"), .daily), day("2026-03-11"))
        XCTAssertEqual(RecurrenceRules.next(day("2026-03-10"), .weekly), day("2026-03-17"))
        XCTAssertEqual(RecurrenceRules.next(day("2026-03-10"), .monthly), day("2026-04-10"))
        XCTAssertEqual(RecurrenceRules.next(day("2026-03-10"), .yearly), day("2027-03-10"))
    }

    func testPreviewsStayInShownMonths() {
        let today = day("2026-03-01")
        let march: Set = [day("2026-03-01")]
        XCTAssertEqual(RecurrenceRules.previews([weekly], today: today, months: march).map(\.date),
                       [day("2026-03-17"), day("2026-03-24"), day("2026-03-31")])
        XCTAssertEqual(RecurrenceRules.previews([weekly], today: today, months: march).first?.id,
                       "recurrence-preview:task-1:2026-03-17")
        let withMay = RecurrenceRules.previews([weekly], today: today, months: [day("2026-03-01"), day("2026-05-01")]).map(\.date)
        XCTAssertEqual(withMay, ["2026-03-17", "2026-03-24", "2026-03-31", "2026-05-05", "2026-05-12", "2026-05-19", "2026-05-26"].map(day))
    }

    func testNoPreviewsForClosedUndatedOrSingleTasks() {
        var done = weekly; done.completedAt = "2026-03-02T12:00:00.000Z"
        var gone = weekly; gone.deletedAt = "2026-03-02T12:00:00.000Z"
        var undated = weekly; undated.dueDate = nil
        var single = weekly; single.recurrence = nil
        XCTAssertTrue(RecurrenceRules.previews([done, gone, undated, single], today: day("2026-03-01"), months: [day("2026-03-01")]).isEmpty)
    }

    func testOverduePreviewsStartAfterToday() {
        var daily = weekly; daily.dueDate = day("2026-03-01"); daily.recurrence = .daily
        let dates = RecurrenceRules.previews([daily], today: day("2026-03-06"), months: [day("2026-03-01")]).map(\.date)
        XCTAssertEqual(dates.first, day("2026-03-07"))
        XCTAssertEqual(dates.last, day("2026-03-31"))
    }

    func testCompletionRollsPastToday() {
        let today = day("2026-03-15")
        XCTAssertEqual(RecurrenceRules.nextAfterCompletion(day("2026-03-10"), .daily, today: today), day("2026-03-16"))
        XCTAssertEqual(RecurrenceRules.nextAfterCompletion(day("2026-03-01"), .weekly, today: today), day("2026-03-22"))
        XCTAssertEqual(RecurrenceRules.nextAfterCompletion(day("2026-03-15"), .daily, today: today), day("2026-03-16"))
        XCTAssertEqual(RecurrenceRules.nextAfterCompletion(day("2026-03-20"), .weekly, today: today), day("2026-03-27"))
        XCTAssertEqual(RecurrenceRules.nextAfterCompletion(day("2026-03-08"), .weekly, today: today), day("2026-03-22"))
        XCTAssertEqual(RecurrenceRules.nextAfterCompletion(day("2020-01-01"), .daily, today: today), day("2026-03-16"))
    }

    func testAnchorDay() {
        let anchor = RecurrenceRules.anchorDay(day("2026-01-31"), recurrenceDay: nil)
        let february = RecurrenceRules.next(day("2026-01-31"), .monthly, anchorDay: anchor)
        XCTAssertEqual(february, day("2026-02-28"))
        XCTAssertEqual(RecurrenceRules.next(february, .monthly, anchorDay: anchor), day("2026-03-31"))

        let leap = RecurrenceRules.anchorDay(day("2028-02-29"), recurrenceDay: nil)
        XCTAssertEqual(RecurrenceRules.next(day("2028-02-29"), .yearly, anchorDay: leap), day("2029-02-28"))
        XCTAssertEqual(RecurrenceRules.next(day("2031-02-28"), .yearly, anchorDay: leap), day("2032-02-29"))

        XCTAssertEqual(RecurrenceRules.anchorDay(day("2026-02-28"), recurrenceDay: 31), 31)
        XCTAssertEqual(RecurrenceRules.anchorDay(day("2026-02-20"), recurrenceDay: 31), 20)
        XCTAssertEqual(RecurrenceRules.nextAfterCompletion(day("2026-01-31"), .monthly, today: day("2026-03-01"), anchorDay: 31), day("2026-03-31"))
    }
}
