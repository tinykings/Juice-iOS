import Foundation
@testable import JuiceCore

func day(_ string: String) -> CalendarDay { CalendarDay(string)! }

// Tests run in a fixed zone, whatever the machine's.
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

// A local time in testCalendar's zone.
func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    utcCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}
