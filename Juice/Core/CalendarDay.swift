import Foundation

// A calendar date with no time or time zone: a task's due date, `YYYY-MM-DD` in sync.
// Arithmetic runs in a fixed Gregorian UTC calendar so it never shifts with daylight
// saving; only `today` and `start(in:)` look at the device's time zone.
struct CalendarDay: Hashable, Comparable, Codable, Sendable, Identifiable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...Self.daysIn(year: year, month: month)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    // Only for values already checked.
    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    // `YYYY-MM-DD` that names a real day.
    init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard string.count == 10, parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let value = CalendarDay(string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a date: \(string)"))
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    var id: String { description }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func < (a: CalendarDay, b: CalendarDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    // MARK: Device time

    // The day `date` falls on in `calendar`'s time zone (the device's by default).
    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(unchecked: parts.year!, parts.month!, parts.day!)
    }

    static func today(_ now: Date = Date(), calendar: Calendar = .current) -> CalendarDay {
        CalendarDay(now, calendar: calendar)
    }

    // Midnight starting this day in `calendar`'s time zone.
    func start(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: Arithmetic

    static func daysIn(year: Int, month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    var daysInMonth: Int { Self.daysIn(year: year, month: month) }

    // Days since 1970-01-01 (proleptic Gregorian).
    var ordinal: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    init(ordinal: Int) {
        let z = ordinal + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        self.init(unchecked: yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    func adding(days: Int) -> CalendarDay { CalendarDay(ordinal: ordinal + days) }

    // The same day `months` later, clamped to that month's length.
    func adding(months: Int, day wanted: Int? = nil) -> CalendarDay {
        let total = year * 12 + (month - 1) + months
        let y = total / 12, m = total % 12 + 1
        return CalendarDay(unchecked: y, m, min(wanted ?? day, Self.daysIn(year: y, month: m)))
    }

    func days(until other: CalendarDay) -> Int { other.ordinal - ordinal }

    // 0 = Sunday … 6 = Saturday.
    var weekday: Int {
        let w = (ordinal + 4) % 7 // 1970-01-01 was a Thursday.
        return w < 0 ? w + 7 : w
    }

    var firstOfMonth: CalendarDay { CalendarDay(unchecked: year, month, 1) }
}
