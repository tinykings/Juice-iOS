import XCTest
@testable import JuiceCore

// Mirrors the website's src/utils/ics.test.ts. "Local" time here is UTC.
final class ICSTests: XCTestCase {
    func wrap(_ lines: [String], _ separator: String = "\n") -> String {
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" + lines.joined(separator: separator) + "\r\nEND:VCALENDAR\r\n"
    }

    func events(_ lines: [String], from: Date = utc(2026, 11, 1), to: Date = utc(2026, 12, 31), _ separator: String = "\n") -> [CalendarEvent] {
        ICS.events(wrap(lines, separator), from: from, to: to, calendar: utcCalendar)
    }

    func testTimedUTCEventWithFoldedEscapedSummary() {
        let result = events(["BEGIN:VEVENT", "UID:a", "DTSTART:20261105T170000Z", "SUMMARY:Team\\, weekly", "  sync", "END:VEVENT"], "\r\n")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Team, weekly sync")
        XCTAssertEqual(result.first?.allDay, false)
        XCTAssertEqual(result.first?.start, utc(2026, 11, 5, 17))
    }

    func testTZIDTimes() {
        let result = events(["BEGIN:VEVENT", "UID:tz", "DTSTART;TZID=America/New_York:20261110T090000", "SUMMARY:Standup", "END:VEVENT"])
        XCTAssertEqual(result.first?.start, utc(2026, 11, 10, 14))
        let windows = events(["BEGIN:VEVENT", "UID:tz", "DTSTART;TZID=Eastern Standard Time:20261110T090000", "SUMMARY:Standup", "END:VEVENT"])
        XCTAssertEqual(windows.first?.start, utc(2026, 11, 10, 14))
    }

    func testMultiDayAllDay() {
        let result = events(["BEGIN:VEVENT", "UID:trip", "DTSTART;VALUE=DATE:20261120", "DTEND;VALUE=DATE:20261123", "SUMMARY:Trip", "END:VEVENT"])
        XCTAssertEqual(result.map(\.date), ["2026-11-20", "2026-11-21", "2026-11-22"].map(day))
        XCTAssertTrue(result.allSatisfy(\.allDay))
    }

    func testWeeklyByDayCountExdate() {
        let result = events(["BEGIN:VEVENT", "UID:w", "DTSTART:20261102T150000", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=5",
                             "EXDATE:20261104T150000", "SUMMARY:Gym", "END:VEVENT"])
        XCTAssertEqual(result.map(\.date), ["2026-11-02", "2026-11-09", "2026-11-11", "2026-11-16"].map(day))
    }

    func testMonthlyNthWeekdayUntil() {
        let result = events(["BEGIN:VEVENT", "UID:m", "DTSTART;VALUE=DATE:20260901", "RRULE:FREQ=MONTHLY;BYDAY=-1FR;UNTIL=20261201",
                             "SUMMARY:Review", "END:VEVENT"], from: utc(2026, 9, 1), to: utc(2027, 3, 1))
        XCTAssertEqual(result.map(\.date), ["2026-09-25", "2026-10-30", "2026-11-27"].map(day))
    }

    func testCountsFromStartBeforeWindow() {
        let result = events(["BEGIN:VEVENT", "UID:d", "DTSTART;VALUE=DATE:20261028", "RRULE:FREQ=DAILY;COUNT=6", "SUMMARY:Daily", "END:VEVENT"])
        XCTAssertEqual(result.map(\.date), ["2026-11-01", "2026-11-02"].map(day))
    }

    func testOverridesAndCancelled() {
        let result = events([
            "BEGIN:VEVENT", "UID:r", "DTSTART:20261103T100000Z", "RRULE:FREQ=WEEKLY;COUNT=3", "SUMMARY:1:1", "END:VEVENT",
            "BEGIN:VEVENT", "UID:r", "RECURRENCE-ID:20261110T100000Z", "DTSTART:20261111T120000Z", "SUMMARY:1:1 (moved)", "END:VEVENT",
            "BEGIN:VEVENT", "UID:x", "DTSTART:20261105T100000Z", "STATUS:CANCELLED", "SUMMARY:Gone", "END:VEVENT",
        ])
        XCTAssertEqual(result.map(\.title), ["1:1", "1:1 (moved)", "1:1"])
        XCTAssertEqual(result[1].start, utc(2026, 11, 11, 12))
    }

    func testIgnoresNestedComponents() {
        let result = events(["BEGIN:VEVENT", "UID:al", "DTSTART;VALUE=DATE:20261112", "SUMMARY:Real title",
                             "BEGIN:VALARM", "SUMMARY:Alarm title", "END:VALARM", "END:VEVENT"])
        XCTAssertEqual(result.first?.title, "Real title")
    }

    func testYearlyAndTimeLabel() {
        let result = events(["BEGIN:VEVENT", "UID:y", "DTSTART:20201130T093000", "RRULE:FREQ=YEARLY", "SUMMARY:Anniversary", "END:VEVENT"])
        XCTAssertEqual(result.map(\.date), [day("2026-11-30")])
        XCTAssertEqual(result.first?.timeLabel(calendar: utcCalendar), "9:30 am")
    }

    func testNormalizesWebcal() {
        XCTAssertEqual(ICS.normalizeURL(" webcal://p01.icloud.com/x.ics ")?.absoluteString, "https://p01.icloud.com/x.ics")
        XCTAssertNil(ICS.normalizeURL("not a link"))
        XCTAssertNil(ICS.normalizeURL("file:///etc/passwd"))
    }
}
