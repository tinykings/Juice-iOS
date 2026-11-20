import Foundation

// A title's @time, its note, and date words like "tomorrow". Ported from the website's
// src/utils/taskTime.ts, taskTitle.ts and dateWords.ts, so a title reads the same in
// both apps.

private func regex(_ pattern: String) -> NSRegularExpression {
    // The patterns are constants; a typo should fail tests, not ship.
    try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
}

private extension String {
    var fullRange: NSRange { NSRange(startIndex..., in: self) }

    func substring(_ range: NSRange) -> String {
        guard range.location != NSNotFound, let r = Range(range, in: self) else { return "" }
        return String(self[r])
    }

    // UTF-16 offsets, the way NSRegularExpression counts.
    func prefix(utf16 offset: Int) -> String { substring(NSRange(location: 0, length: offset)) }
    func dropping(utf16 range: NSRange) -> String {
        let ns = self as NSString
        return ns.replacingCharacters(in: range, with: "")
    }

    func collapsingSpaces() -> String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - @time

enum TaskTime {
    // Not part of an email address or handle ("bob@123.com"), and not followed by more of a word.
    private static let pattern = regex(#"(?<![\w.@])@(\d+(?::\d{2})?(?:pm|am)?)(?![\w:]|\.\w)"#)

    // Minutes after midnight for an @time's text (9am, 530, 2:30pm), or nil when it isn't
    // a real time. Without am/pm, 1–6 o'clock reads as afternoon and 7–11 as morning.
    static func parse(_ text: String) -> Int? {
        let clean = text.lowercased()
        let isPM = clean.hasSuffix("pm"), isAM = clean.hasSuffix("am")
        let digits = clean.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "")
        var hours: Int, minutes = 0
        if digits.contains(":") {
            let parts = digits.split(separator: ":", omittingEmptySubsequences: false)
            hours = Int(parts[0]) ?? 0
            minutes = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        } else {
            let number = Int(digits) ?? 0
            hours = number >= 100 ? number / 100 : number
            minutes = number >= 100 ? number % 100 : 0
        }
        if isPM && hours < 12 { hours += 12 }
        else if isAM && hours == 12 { hours = 0 }
        else if !isPM && !isAM && (1...6).contains(hours) { hours += 12 }
        return hours > 23 || minutes > 59 ? nil : hours * 60 + minutes
    }

    struct Match: Equatable {
        let range: NSRange
        let text: String
        let minutes: Int
    }

    // The first real @time in a title. "@99" and the like stay ordinary text.
    static func find(in title: String) -> Match? {
        for match in pattern.matches(in: title, range: title.fullRange) {
            if let minutes = parse(title.substring(match.range(at: 1))) {
                return Match(range: match.range, text: title.substring(match.range), minutes: minutes)
            }
        }
        return nil
    }

    static func minutes(in title: String) -> Int? { find(in: title)?.minutes }

    // "2 pm" or "9:30 am".
    static func label(minutes: Int) -> String {
        let hours24 = minutes / 60, mins = minutes % 60
        let suffix = hours24 >= 12 ? "pm" : "am"
        let hours12 = hours24 % 12 == 0 ? 12 : hours24 % 12
        return mins == 0 ? "\(hours12) \(suffix)" : "\(hours12):\(String(format: "%02d", mins)) \(suffix)"
    }

    static func label(for title: String) -> String? { minutes(in: title).map(label(minutes:)) }

    // The title with its real @time tokens removed.
    static func strip(_ title: String) -> String {
        var result = title
        for match in pattern.matches(in: title, range: title.fullRange).reversed()
        where parse(title.substring(match.range(at: 1))) != nil {
            result = result.dropping(utf16: match.range)
        }
        return result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Timed tasks first, earliest first; everything else alphabetically.
    static func compare(_ a: String, _ b: String) -> Bool {
        let ta = minutes(in: a), tb = minutes(in: b)
        switch (ta, tb) {
        case (.some, .none): return true
        case (.none, .some): return false
        case let (.some(x), .some(y)) where x != y: return x < y
        default: return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}

// MARK: - Title and note

enum TaskTitle {
    // A period after one of these belongs to the name ("Dr. Smith"), not the end of the title.
    private static let abbreviations: Set<String> = ["dr", "mr", "mrs", "ms", "mx", "prof", "st", "mt", "vs", "jr", "sr"]
    private static let periodPattern = regex(#"\.(?=\s|$)"#)
    private static let lastWord = regex(#"\S+$"#)

    // Where the title ends and the note begins (a UTF-16 offset): the first period
    // followed by a space or the end. Periods inside "$12.50" or "example.com" don't count.
    static func noteSeparator(_ value: String) -> Int? {
        for match in periodPattern.matches(in: value, range: value.fullRange) {
            let before = value.prefix(utf16: match.range.location)
            let word = lastWord.firstMatch(in: before, range: before.fullRange).map { before.substring($0.range).lowercased() }
            if word == nil || !abbreviations.contains(word!) { return match.range.location }
        }
        return nil
    }

    static func split(_ value: String) -> (title: String, note: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = noteSeparator(trimmed) else { return (trimmed, "") }
        let ns = trimmed as NSString
        let title = ns.substring(to: index).trimmingCharacters(in: .whitespacesAndNewlines)
        let note = ns.substring(from: index + 1).trimmingCharacters(in: .whitespacesAndNewlines)
        return (title.isEmpty ? trimmed : title, note)
    }

    struct Parts: Equatable {
        let title: String
        let note: String
    }

    // What a task shows: its title without the @time, and a note made of what follows the
    // title plus the separate notes field.
    static func parts(title: String, notes: String) -> Parts {
        let stripped = TaskTime.strip(title)
        let split = split(stripped.isEmpty ? title : stripped)
        let note = [split.note, notes.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        return Parts(title: split.title, note: note.joined(separator: "\n"))
    }
}

// MARK: - Date words

enum DateWords {
    struct Match: Equatable {
        let word: String
        let date: CalendarDay
        let range: NSRange
    }

    // "sun" and "sat" are left out: they're everyday words ("sun cream", "sat down").
    private static let dayNames: [(String, Int)] = [
        ("sunday", 0), ("monday", 1), ("mon", 1), ("tuesday", 2), ("tues", 2), ("tue", 2),
        ("wednesday", 3), ("wed", 3), ("thursday", 4), ("thurs", 4), ("thur", 4), ("thu", 4),
        ("friday", 5), ("fri", 5), ("saturday", 6),
    ]
    private static let monthNames: [(String, Int)] = [
        ("january", 1), ("jan", 1), ("february", 2), ("feb", 2), ("march", 3), ("mar", 3),
        ("april", 4), ("apr", 4), ("may", 5), ("june", 6), ("jun", 6), ("july", 7), ("jul", 7),
        ("august", 8), ("aug", 8), ("september", 9), ("sep", 9), ("october", 10), ("oct", 10),
        ("november", 11), ("nov", 11), ("december", 12), ("dec", 12),
    ]
    private static let monthIndex = Dictionary(uniqueKeysWithValues: monthNames)

    // Like a trailing \b, but also rejects apostrophes so "tomorrow's" isn't a date.
    private static let end = "(?![\\w'’])"

    private typealias Compute = (NSTextCheckingResult, String, CalendarDay) -> CalendarDay

    private static let entries: [(NSRegularExpression, Compute)] = {
        let months = monthNames.map(\.0).joined(separator: "|")
        var list: [(NSRegularExpression, Compute)] = [
            (regex("\\bnext week\(end)"), { _, _, today in
                let until = (8 - today.weekday) % 7
                return today.adding(days: until == 0 ? 7 : until)
            }),
            (regex("\\bnext month\(end)"), { _, _, today in today.firstOfMonth.adding(months: 1) }),
            (regex("\\b(\(months))\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s*(\\d{4}))?\(end)"), { match, text, today in
                monthDay(month: text.substring(match.range(at: 1)), day: text.substring(match.range(at: 2)),
                         year: text.substring(match.range(at: 3)), today: today)
            }),
            (regex("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(\(months))(?:,?\\s*(\\d{4}))?\(end)"), { match, text, today in
                monthDay(month: text.substring(match.range(at: 2)), day: text.substring(match.range(at: 1)),
                         year: text.substring(match.range(at: 3)), today: today)
            }),
            (regex("\\btomorrow\(end)"), { _, _, today in today.adding(days: 1) }),
            (regex("\\btoday\(end)"), { _, _, today in today }),
        ]
        for (name, day) in dayNames {
            list.append((regex("\\bnext \(name)\(end)"), { _, _, today in weekday(day, from: today, allowToday: false) }))
            list.append((regex("\\b\(name)\(end)"), { _, _, today in weekday(day, from: today, allowToday: true) }))
        }
        return list
    }()

    private static func weekday(_ target: Int, from today: CalendarDay, allowToday: Bool) -> CalendarDay {
        var diff = target - today.weekday
        if diff < 0 { diff += 7 }
        if diff == 0 && !allowToday { diff = 7 }
        return today.adding(days: diff)
    }

    // A month and day without a year means the next one on or after today.
    private static func monthDay(month: String, day: String, year: String, today: CalendarDay) -> CalendarDay {
        let m = monthIndex[month.lowercased()] ?? 1
        let y = Int(year) ?? today.year
        let d = min(max(Int(day) ?? 1, 1), CalendarDay.daysIn(year: y, month: m))
        let date = CalendarDay(year: y, month: m, day: d)!
        guard year.isEmpty, date < today else { return date }
        return CalendarDay(year: y + 1, month: m, day: min(d, CalendarDay.daysIn(year: y + 1, month: m)))!
    }

    // The earliest date word in the text.
    static func find(in text: String, today: CalendarDay) -> Match? {
        var earliest: Match?
        for (pattern, compute) in entries {
            guard let match = pattern.firstMatch(in: text, range: text.fullRange) else { continue }
            if earliest == nil || match.range.location < earliest!.range.location {
                earliest = Match(word: text.substring(match.range), date: compute(match, text, today), range: match.range)
            }
        }
        return earliest
    }

    // Like `find`, but ignores the note.
    static func findInTitle(_ value: String, today: CalendarDay) -> Match? {
        guard let index = TaskTitle.noteSeparator(value) else { return find(in: value, today: today) }
        return find(in: value.prefix(utf16: index), today: today)
    }

    static func remove(_ match: Match, from text: String) -> String {
        text.dropping(utf16: match.range).collapsingSpaces()
    }
}

// MARK: - New tasks from text

// What the add field, Siri and Shortcuts make from typed or spoken text: "Call mom
// tomorrow @5pm" becomes "Call mom @5pm" due tomorrow. A date word only sets the date
// when no date was given; without either, the task is due today, as on the website.
struct TaskDraft: Equatable, Sendable {
    var title: String
    var notes: String
    var dueDate: CalendarDay?

    init(text: String, notes: String = "", dueDate: CalendarDay? = nil, today: CalendarDay, undatedIfNoDate: Bool = false) {
        var title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var due = dueDate
        if let match = DateWords.findInTitle(title, today: today) {
            let removed = DateWords.remove(match, from: title)
            if !removed.isEmpty {
                title = removed
                if due == nil { due = match.date }
            }
        }
        self.title = String(title.prefix(SyncCodec.maxTitle))
        self.notes = String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SyncCodec.maxNotes))
        self.dueDate = due ?? (undatedIfNoDate ? nil : today)
    }

    // Text taken as it is, for the add form, which has already applied any date word.
    init(exactTitle: String, notes: String = "", dueDate: CalendarDay?) {
        title = String(exactTitle.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SyncCodec.maxTitle))
        self.notes = String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SyncCodec.maxNotes))
        self.dueDate = dueDate
    }

    var isEmpty: Bool { title.isEmpty }
}
