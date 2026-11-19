import XCTest
@testable import JuiceCore

final class CalendarDayTests: XCTestCase {
    func testParsesOnlyRealDays() {
        XCTAssertEqual(CalendarDay("2026-02-28")?.description, "2026-02-28")
        XCTAssertNil(CalendarDay("2026-02-29"))
        XCTAssertNotNil(CalendarDay("2028-02-29"))
        XCTAssertNil(CalendarDay("2026-2-28"))
        XCTAssertNil(CalendarDay("2026-13-01"))
        XCTAssertNil(CalendarDay(""))
        XCTAssertNil(CalendarDay("２０２６-01-01"))
    }

    func testOrdinalRoundTrips() {
        for string in ["1970-01-01", "2000-02-29", "2026-11-19", "1899-12-31", "2400-03-01"] {
            let value = day(string)
            XCTAssertEqual(CalendarDay(ordinal: value.ordinal), value)
        }
        XCTAssertEqual(day("1970-01-01").ordinal, 0)
        XCTAssertEqual(day("2026-12-31").adding(days: 1), day("2027-01-01"))
    }

    func testWeekday() {
        XCTAssertEqual(day("2026-11-19").weekday, 4) // Thursday
        XCTAssertEqual(day("2026-11-22").weekday, 0) // Sunday
    }

    func testAddingMonthsClamps() {
        XCTAssertEqual(day("2026-01-31").adding(months: 1), day("2026-02-28"))
        XCTAssertEqual(day("2026-02-28").adding(months: 1, day: 31), day("2026-03-31"))
        XCTAssertEqual(day("2026-11-15").adding(months: 2), day("2027-01-15"))
    }

    func testTodayUsesTheCalendarsZone() {
        // 03:00 UTC on Nov 20 is still Nov 19 in New York.
        XCTAssertEqual(CalendarDay.today(utc(2026, 11, 20, 3), calendar: testCalendar), day("2026-11-19"))
        XCTAssertEqual(day("2026-11-19").start(in: testCalendar), local(2026, 11, 19))
    }

    func testCodableAsString() throws {
        let data = try JSONEncoder().encode([day("2026-11-19")])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["2026-11-19"]"#)
        XCTAssertEqual(try JSONDecoder().decode([CalendarDay].self, from: data), [day("2026-11-19")])
    }
}
