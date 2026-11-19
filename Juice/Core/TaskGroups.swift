import Foundation

// One row in a day's list: a task or a read-only event from the subscribed calendar.
enum ListItem: Identifiable, Equatable, Sendable {
    case task(JuiceTask)
    case event(CalendarEvent)

    var id: String {
        switch self {
        case .task(let task): "task:" + task.id
        case .event(let event): "event:" + event.id
        }
    }
}

struct TaskGroup: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case overdue
        case day(CalendarDay)
        case month(CalendarDay)
    }

    let kind: Kind
    let label: String
    // A short date beside the label, like "Tue, Nov 3".
    let detail: String?
    let items: [ListItem]

    var id: String { label }
    var isOverdue: Bool { kind == .overdue }
    var isToday: Bool { if case .day = kind, label == "Today" { true } else { false } }

    // The day a new task added from this group's header gets.
    var day: CalendarDay? {
        if case .day(let day) = kind { day } else { nil }
    }
}

// Overdue, Today, each of the next seven days, then one group per later month. Ported
// from the website's src/utils/taskGroups.ts.
enum TaskGroups {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }
    private static let formatters: [String: DateFormatter] = Dictionary(
        uniqueKeysWithValues: ["EEE, MMM d", "MMM d", "EEEE", "MMMM yyyy", "MMM d, yyyy"].map { ($0, formatter($0)) })

    static func format(_ day: CalendarDay, _ pattern: String) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return (formatters[pattern] ?? formatter(pattern)).string(from: day.start(in: utc))
    }

    // Earlier date first, then by time and title.
    static func byDateAndTime(_ a: JuiceTask, _ b: JuiceTask) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return true
        case (_?, nil): return false
        default: return TaskTime.compare(a.title, b.title)
        }
    }

    // Tasks first (by time, then title), then events by start time.
    static func dayItems(_ tasks: [JuiceTask], _ events: [CalendarEvent]) -> [ListItem] {
        tasks.sorted { TaskTime.compare($0.title, $1.title) }.map(ListItem.task)
            + events.sorted { ($0.start, $0.title) < ($1.start, $1.title) }.map(ListItem.event)
    }

    static func build(open: [JuiceTask], events: [CalendarEvent] = [], today: CalendarDay) -> [TaskGroup] {
        var groups: [TaskGroup] = []
        let dated = open.filter { $0.dueDate != nil }
        let undated = open.filter { $0.dueDate == nil }
        let overdue = dated.filter { $0.dueDate! < today }
        if !overdue.isEmpty || !undated.isEmpty {
            // Oldest first; undated tasks follow the ones that were due.
            let items = overdue.sorted(by: byDateAndTime) + undated.sorted { TaskTime.compare($0.title, $1.title) }
            groups.append(TaskGroup(kind: .overdue, label: "Overdue", detail: nil, items: items.map(ListItem.task)))
        }

        let tasksByDay = Dictionary(grouping: dated, by: { $0.dueDate! })
        let eventsByDay = Dictionary(grouping: events, by: \.date)
        for offset in 0...7 {
            let day = today.adding(days: offset)
            let label = switch offset {
            case 0: "Today"
            case 1: "Tomorrow"
            default: format(day, "EEEE")
            }
            groups.append(TaskGroup(kind: .day(day), label: label,
                                    detail: format(day, offset <= 1 ? "EEE, MMM d" : "MMM d"),
                                    items: dayItems(tasksByDay[day] ?? [], eventsByDay[day] ?? [])))
        }

        let weekEnd = today.adding(days: 7)
        let later = Dictionary(grouping: dated.filter { $0.dueDate! > weekEnd }, by: { $0.dueDate!.firstOfMonth })
        for month in later.keys.sorted() {
            groups.append(TaskGroup(kind: .month(month), label: format(month, "MMMM yyyy"), detail: nil,
                                    items: later[month]!.sorted(by: byDateAndTime).map(ListItem.task)))
        }
        return groups
    }

    // The date on a task card, for groups whose header doesn't already say which day.
    static func dateLabel(_ task: JuiceTask, in group: TaskGroup, today: CalendarDay) -> String? {
        switch group.kind {
        case .overdue:
            guard let due = task.dueDate else { return "No date" }
            return format(due, due.year == today.year ? "MMM d" : "MMM d, yyyy")
        case .month:
            return task.dueDate.map { format($0, "EEE, MMM d") }
        case .day:
            return nil
        }
    }
}
