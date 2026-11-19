import Foundation

// Recurring tasks: when the next occurrence falls, and the read-only previews the
// calendar shows. Ported from the website's src/utils/taskRecurrence.ts.
enum RecurrenceRules {
    // The day of the month a monthly or yearly series aims for. A task on the 31st lands
    // on Feb 28 and returns to Mar 31 because the occurrence remembers 31 in
    // `recurrenceDay`. A stored day only counts while the date is its month's last day;
    // any other date means the task was moved, so its own day takes over.
    static func anchorDay(_ due: CalendarDay, recurrenceDay: Int?) -> Int {
        if let stored = recurrenceDay, stored > due.day, stored <= 31, due.day == due.daysInMonth {
            return stored
        }
        return due.day
    }

    static func next(_ date: CalendarDay, _ recurrence: Recurrence, anchorDay: Int? = nil) -> CalendarDay {
        switch recurrence {
        case .daily: date.adding(days: 1)
        case .weekly: date.adding(days: 7)
        case .monthly: date.adding(months: 1, day: anchorDay)
        case .yearly: date.adding(months: 12, day: anchorDay)
        }
    }

    // The date of the occurrence that replaces a completed one. Overdue tasks skip missed
    // occurrences so the new one isn't already overdue.
    static func nextAfterCompletion(_ date: CalendarDay, _ recurrence: Recurrence, today: CalendarDay,
                                    anchorDay: Int? = nil) -> CalendarDay {
        var next = next(date, recurrence, anchorDay: anchorDay)
        if next <= today {
            // Jump close to today in one step, then walk the rest.
            switch recurrence {
            case .daily:
                next = today.adding(days: 1)
            case .weekly:
                let weeks = next.days(until: today) / 7
                next = next.adding(days: weeks * 7)
            case .monthly, .yearly:
                break
            }
            var guardCount = 0
            while next <= today, guardCount < 100_000 {
                next = self.next(next, recurrence, anchorDay: anchorDay)
                guardCount += 1
            }
        }
        return next
    }

    struct Preview: Equatable, Sendable {
        let task: JuiceTask
        let date: CalendarDay
        var id: String { "recurrence-preview:\(task.id):\(date)" }
    }

    // Future occurrences of open recurring tasks, only after today and only within months
    // already shown (`months`, as their first days). They're never stored or synced.
    static func previews(_ tasks: [JuiceTask], today: CalendarDay, months: Set<CalendarDay>) -> [Preview] {
        guard let last = months.max() else { return [] }
        var result: [Preview] = []
        for task in tasks where task.isOpen {
            guard let due = task.dueDate, let recurrence = task.recurrence else { continue }
            let anchor = anchorDay(due, recurrenceDay: task.recurrenceDay)
            var date = due
            for _ in 0..<100_000 {
                let following = next(date, recurrence, anchorDay: anchor)
                guard following > date, following.firstOfMonth <= last else { break }
                date = following
                if date > today, months.contains(date.firstOfMonth) {
                    result.append(Preview(task: task, date: date))
                }
            }
        }
        return result
    }
}
