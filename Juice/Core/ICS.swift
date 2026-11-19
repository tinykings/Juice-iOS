import Foundation

// An event from the subscribed calendar, shown read-only beside tasks.
struct CalendarEvent: Codable, Equatable, Identifiable, Sendable {
    // Unique per occurrence.
    let id: String
    let title: String
    // The local day it's shown on.
    let date: CalendarDay
    let allDay: Bool
    // Start instant; for all-day events, local midnight of `date`.
    let start: Date

    // "9:30 AM" for timed events.
    func timeLabel(calendar: Calendar = .current) -> String? {
        guard !allDay else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: start)
        return TaskTime.label(minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }
}

// A minimal iCalendar (.ics) reader for a subscribed calendar. Ported from the website's
// src/utils/ics.ts.
//
// Supports line folding, text escapes, all-day and timed events (UTC, TZID or floating),
// multi-day all-day events, RRULE (DAILY/WEEKLY/MONTHLY/YEARLY with INTERVAL, COUNT,
// UNTIL, BYDAY, BYMONTHDAY, BYMONTH), EXDATE, RECURRENCE-ID overrides and
// STATUS:CANCELLED. Events are expanded into the given window.
enum ICS {
    private static let maxIterations = 20_000
    private static let maxAllDaySpan = 31

    private struct Prop {
        let name: String
        let params: [String: String]
        let value: String
    }

    private struct DateValue {
        var day: CalendarDay
        var hour = 0, minute = 0, second = 0
        var allDay: Bool
        // UTC, an IANA zone, or nil for floating (local) time.
        var zone: TimeZone?

        func on(_ day: CalendarDay) -> DateValue {
            var copy = self
            copy.day = day
            return copy
        }
    }

    // webcal:// links are https.
    static func normalizeURL(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: #"^webcals?://"#, options: [.regularExpression, .caseInsensitive]) {
            value.replaceSubrange(range, with: "https://")
        }
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    static func looksLikeCalendar(_ text: String) -> Bool { text.contains("BEGIN:VCALENDAR") }

    // MARK: Lines

    private static func unfold(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
            .components(separatedBy: "\n")
    }

    private static func parseLine(_ line: String) -> Prop? {
        // Split name;params from the value at the first colon outside quotes.
        var inQuotes = false
        var colon: String.Index?
        for index in line.indices {
            let ch = line[index]
            if ch == "\"" { inQuotes.toggle() } else if ch == ":" && !inQuotes { colon = index; break }
        }
        guard let colon else { return nil }
        let head = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        let parts = head.split(separator: ";", omittingEmptySubsequences: false)
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let eq = part.firstIndex(of: "="), eq > part.startIndex else { continue }
            var v = String(part[part.index(after: eq)...])
            if v.hasPrefix("\"") { v.removeFirst() }
            if v.hasSuffix("\"") { v.removeLast() }
            params[part[..<eq].uppercased()] = v
        }
        return Prop(name: parts[0].uppercased(), params: params, value: value)
    }

    private static func unescape(_ value: String) -> String {
        var result = ""
        var escaping = false
        for ch in value {
            if escaping {
                switch ch {
                case "n", "N": result.append(" ")
                case "\\", ";", ",": result.append(ch)
                default: result.append("\\"); result.append(ch)
                }
                escaping = false
            } else if ch == "\\" {
                escaping = true
            } else {
                result.append(ch)
            }
        }
        if escaping { result.append("\\") }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseEvents(_ text: String) -> [[Prop]] {
        var events: [[Prop]] = []
        var stack: [String] = []
        var current: [Prop]?
        for line in unfold(text) where !line.isEmpty {
            guard let prop = parseLine(line) else { continue }
            if prop.name == "BEGIN" {
                let component = prop.value.trimmingCharacters(in: .whitespaces).uppercased()
                stack.append(component)
                if component == "VEVENT" { current = [] }
                continue
            }
            if prop.name == "END" {
                if stack.popLast() == "VEVENT", let event = current {
                    events.append(event)
                    current = nil
                }
                continue
            }
            if current != nil, stack.last == "VEVENT" { current!.append(prop) }
        }
        return events
    }

    // MARK: Dates

    private static let windowsZones: [String: String] = [
        "Eastern Standard Time": "America/New_York",
        "Central Standard Time": "America/Chicago",
        "Mountain Standard Time": "America/Denver",
        "US Mountain Standard Time": "America/Phoenix",
        "Pacific Standard Time": "America/Los_Angeles",
        "Alaskan Standard Time": "America/Anchorage",
        "Hawaiian Standard Time": "Pacific/Honolulu",
        "GMT Standard Time": "Europe/London",
        "W. Europe Standard Time": "Europe/Berlin",
        "Romance Standard Time": "Europe/Paris",
        "Central Europe Standard Time": "Europe/Budapest",
        "AUS Eastern Standard Time": "Australia/Sydney",
        "Tokyo Standard Time": "Asia/Tokyo",
        "India Standard Time": "Asia/Kolkata",
        "UTC": "UTC",
    ]

    private static func zone(_ tzid: String?) -> TimeZone? {
        guard var id = tzid else { return nil }
        if id.hasPrefix("/") { id.removeFirst() }
        return TimeZone(identifier: windowsZones[id] ?? id) // Unknown: floating.
    }

    private static func digits(_ s: Substring) -> Int? {
        s.allSatisfy { $0.isASCII && $0.isNumber } ? Int(s) : nil
    }

    private static func parseDate(_ prop: Prop, _ raw: String? = nil) -> DateValue? {
        let value = (raw ?? prop.value).trimmingCharacters(in: .whitespaces)
        let chars = Array(value)
        func num(_ from: Int, _ length: Int) -> Int? {
            guard chars.count >= from + length else { return nil }
            return digits(Substring(String(chars[from..<from + length])))
        }
        guard let y = num(0, 4), let m = num(4, 2), let d = num(6, 2),
              let day = CalendarDay(year: y, month: m, day: d) else { return nil }
        if chars.count == 8 || prop.params["VALUE"] == "DATE" {
            return DateValue(day: day, allDay: true)
        }
        // YYYYMMDDTHHMM[SS][Z]
        guard chars.count >= 13, chars[8] == "T", let h = num(9, 2), let min = num(11, 2) else { return nil }
        var index = 13
        var s = 0
        if let seconds = num(13, 2) { s = seconds; index = 15 }
        let utc = index < chars.count && chars[index] == "Z"
        guard index + (utc ? 1 : 0) == chars.count else { return nil }
        let tz = utc ? TimeZone(identifier: "UTC") : zone(prop.params["TZID"])
        return DateValue(day: day, hour: h, minute: min, second: s, allDay: false, zone: tz)
    }

    private static func instant(_ v: DateValue, local: Calendar) -> Date {
        var calendar = local
        if !v.allDay, let zone = v.zone { calendar.timeZone = zone }
        return calendar.date(from: DateComponents(year: v.day.year, month: v.day.month, day: v.day.day,
                                                  hour: v.hour, minute: v.minute, second: v.second))!
    }

    // MARK: Rules

    private struct ByDay {
        let day: Int
        let n: Int
    }

    private static let dayCodes = ["SU": 0, "MO": 1, "TU": 2, "WE": 3, "TH": 4, "FR": 5, "SA": 6]

    private static func parseByDay(_ value: String?) -> [ByDay] {
        guard let value else { return [] }
        return value.split(separator: ",").compactMap { part in
            let text = part.trimmingCharacters(in: .whitespaces).uppercased()
            guard text.count >= 2, let day = dayCodes[String(text.suffix(2))] else { return nil }
            let prefix = text.dropLast(2)
            if prefix.isEmpty { return ByDay(day: day, n: 0) }
            guard prefix.count <= 3, let n = Int(prefix), abs(n) <= 99 else { return nil }
            return ByDay(day: day, n: n)
        }
    }

    private static func parseNumbers(_ value: String?) -> [Int] {
        guard let value else { return [] }
        return value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 != 0 }
    }

    // Days in a month matching BYDAY (with optional ordinals) or BYMONTHDAY.
    private static func monthDays(_ year: Int, _ month: Int, _ byDay: [ByDay], _ byMonthDay: [Int], fallback: Int) -> [Int] {
        let total = CalendarDay.daysIn(year: year, month: month)
        var result = Set<Int>()
        if !byDay.isEmpty {
            let first = CalendarDay(year: year, month: month, day: 1)!
            for rule in byDay {
                let matches = (1...total).filter { (first.weekday + $0 - 1) % 7 == rule.day }
                if rule.n == 0 { result.formUnion(matches) }
                else {
                    let index = rule.n > 0 ? rule.n - 1 : matches.count + rule.n
                    if matches.indices.contains(index) { result.insert(matches[index]) }
                }
            }
            if !byMonthDay.isEmpty {
                let allowed = Set(byMonthDay.map { $0 > 0 ? $0 : total + $0 + 1 })
                return result.filter(allowed.contains).sorted()
            }
        } else if !byMonthDay.isEmpty {
            for n in byMonthDay {
                let d = n > 0 ? n : total + n + 1
                if (1...total).contains(d) { result.insert(d) }
            }
        } else if fallback <= total {
            result.insert(fallback)
        }
        return result.sorted()
    }

    // The occurrence days of an RRULE, in order, until past `windowEnd`.
    private static func expand(_ rule: [String: String], _ start: DateValue, windowEnd: Date, local: Calendar) -> [CalendarDay] {
        let interval = max(1, Int(rule["INTERVAL"] ?? "") ?? 1)
        let byDay = parseByDay(rule["BYDAY"])
        let byMonthDay = parseNumbers(rule["BYMONTHDAY"])
        let byMonth = parseNumbers(rule["BYMONTH"])
        let s = start.day
        var out: [CalendarDay] = []
        func pastEnd(_ day: CalendarDay) -> Bool { instant(start.on(day), local: local) > windowEnd }

        switch rule["FREQ"]?.uppercased() {
        case "DAILY":
            var i = 0
            for _ in 0..<maxIterations {
                let day = s.adding(days: i)
                i += interval
                if pastEnd(day) { break }
                if !byMonth.isEmpty && !byMonth.contains(day.month) { continue }
                if !byDay.isEmpty && !byDay.contains(where: { $0.day == day.weekday }) { continue }
                out.append(day)
            }
        case "WEEKLY":
            let days = byDay.isEmpty ? [s.weekday] : Array(Set(byDay.map(\.day)))
            // Weeks start on Monday (RFC 5545's default WKST).
            let weekStart = s.adding(days: -((s.weekday + 6) % 7))
            let offsets = days.map { ($0 + 6) % 7 }.sorted()
            var week = 0
            for _ in 0..<maxIterations {
                let base = weekStart.adding(days: week * 7)
                week += interval
                if pastEnd(base) { break }
                for offset in offsets {
                    let day = base.adding(days: offset)
                    if day >= s { out.append(day) }
                }
            }
        case "MONTHLY":
            var i = 0
            for _ in 0..<maxIterations {
                let month = s.firstOfMonth.adding(months: i)
                i += interval
                if pastEnd(month) { break }
                if !byMonth.isEmpty && !byMonth.contains(month.month) { continue }
                for d in monthDays(month.year, month.month, byDay, byMonthDay, fallback: s.day) {
                    let day = CalendarDay(year: month.year, month: month.month, day: d)!
                    if day >= s { out.append(day) }
                }
            }
        case "YEARLY":
            let months = byMonth.isEmpty ? [s.month] : byMonth.filter { (1...12).contains($0) }.sorted()
            let fixedDay = byDay.isEmpty && byMonthDay.isEmpty ? s.day : nil
            var i = 0
            for _ in 0..<maxIterations {
                let y = s.year + i
                i += interval
                guard y <= 9999, !pastEnd(CalendarDay(year: y, month: 1, day: 1)!) else { break }
                for m in months {
                    let days = fixedDay.map { $0 <= CalendarDay.daysIn(year: y, month: m) ? [$0] : [] }
                        ?? monthDays(y, m, byDay, byMonthDay, fallback: s.day)
                    for d in days {
                        let day = CalendarDay(year: y, month: m, day: d)!
                        if day >= s { out.append(day) }
                    }
                }
            }
        default:
            out.append(s)
        }
        return out
    }

    private static func parseRule(_ value: String) -> [String: String] {
        var rule: [String: String] = [:]
        for part in value.split(separator: ";") {
            guard let eq = part.firstIndex(of: "="), eq > part.startIndex else { continue }
            rule[part[..<eq].uppercased()] = String(part[part.index(after: eq)...])
        }
        return rule
    }

    private static func occurrenceKey(_ date: Date, allDay: Bool, local: Calendar) -> String {
        allDay ? CalendarDay(date, calendar: local).description : String(Int(date.timeIntervalSince1970))
    }

    // MARK: Events

    // Event occurrences in a feed that start within the window, sorted by start time.
    static func events(_ text: String, from windowStart: Date, to windowEnd: Date, calendar local: Calendar = .current) -> [CalendarEvent] {
        let raw = parseEvents(text)
        func first(_ event: [Prop], _ name: String) -> Prop? { event.first { $0.name == name } }

        // RECURRENCE-ID overrides, so the master series skips those slots.
        var overrides: [String: Set<String>] = [:]
        for event in raw {
            guard let rid = first(event, "RECURRENCE-ID"), let value = parseDate(rid) else { continue }
            let uid = first(event, "UID")?.value ?? ""
            overrides[uid, default: []].insert(occurrenceKey(instant(value, local: local), allDay: value.allDay, local: local))
        }

        var result: [CalendarEvent] = []
        for event in raw {
            if first(event, "STATUS")?.value.trimmingCharacters(in: .whitespaces).uppercased() == "CANCELLED" { continue }
            guard let startProp = first(event, "DTSTART"), let start = parseDate(startProp) else { continue }
            let uid = first(event, "UID")?.value ?? "\(startProp.value)-\(result.count)"
            let summary = unescape(first(event, "SUMMARY")?.value ?? "")
            let title = summary.isEmpty ? "Busy" : summary

            // All-day events can span several days (DTEND is exclusive).
            var span = 1
            if start.allDay, let endProp = first(event, "DTEND"), let end = parseDate(endProp) {
                span = min(maxAllDaySpan, max(1, start.day.days(until: end.day)))
            }

            var exdates = Set<String>()
            for prop in event where prop.name == "EXDATE" {
                for part in prop.value.split(separator: ",") {
                    if let value = parseDate(prop, String(part)) {
                        exdates.insert(occurrenceKey(instant(value, local: local), allDay: value.allDay || start.allDay, local: local))
                    }
                }
            }

            let isOverride = first(event, "RECURRENCE-ID") != nil
            let rule = isOverride ? nil : first(event, "RRULE").map { parseRule($0.value) }
            let count = rule?["COUNT"].flatMap { Int($0) } ?? Int.max
            var until = Date.distantFuture
            if let text = rule?["UNTIL"], let value = parseDate(Prop(name: "UNTIL", params: [:], value: text)) {
                if value.allDay {
                    var endOfDay = value
                    endOfDay.hour = 23; endOfDay.minute = 59; endOfDay.second = 59
                    until = instant(endOfDay, local: local)
                } else {
                    until = instant(value, local: local)
                }
            }
            let skipped = overrides[uid] ?? []
            let days = rule.map { expand($0, start, windowEnd: windowEnd, local: local) } ?? [start.day]

            var produced = 0
            for day in days {
                if produced >= count { break }
                let at = instant(start.on(day), local: local)
                if at > until { break }
                produced += 1
                let key = occurrenceKey(at, allDay: start.allDay, local: local)
                if exdates.contains(key) || (!isOverride && skipped.contains(key)) { continue }

                for offset in 0..<span {
                    let shown = day.adding(days: offset)
                    let dayStart = start.allDay ? shown.start(in: local) : at
                    // Keep events that overlap the window; multi-day ones only on visible days.
                    if dayStart < windowStart && (start.allDay || offset == 0) {
                        if !start.allDay { break }
                        continue
                    }
                    if dayStart > windowEnd { break }
                    result.append(CalendarEvent(
                        id: "\(uid)|\(key)|\(offset)", title: title,
                        date: start.allDay ? shown : CalendarDay(at, calendar: local),
                        allDay: start.allDay, start: dayStart))
                    if !start.allDay { break }
                }
            }
        }
        return result.sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }
}
