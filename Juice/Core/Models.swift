import Foundation

enum Recurrence: String, Codable, CaseIterable, Sendable, Identifiable {
    case daily, weekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    // Monthly and yearly series remember a day some months lack (`recurrenceDay`).
    var usesAnchorDay: Bool { self == .monthly || self == .yearly }
}

// One task, as synced in a JuiceTask record (docs/sync-schema.md).
struct JuiceTask: Codable, Equatable, Identifiable, Sendable {
    var id: String
    // May hold an @time and, after the first sentence-ending period, a note (TaskTitle).
    var title: String
    var notes: String = ""
    var dueDate: CalendarDay?
    // Only with a due date.
    var recurrence: Recurrence?
    // 29–31: the day a monthly or yearly series returns to after a shorter month.
    var recurrenceDay: Int?
    // The id of the task that started this recurring series.
    var seriesID: String?
    var occurrence = 0
    // ISO 8601 UTC with milliseconds.
    var createdAt: String
    var completedAt: String?
    var deletedAt: String?

    init(id: String, title: String, notes: String = "", dueDate: CalendarDay? = nil,
         recurrence: Recurrence? = nil, recurrenceDay: Int? = nil, seriesID: String? = nil,
         occurrence: Int = 0, createdAt: String, completedAt: String? = nil, deletedAt: String? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.recurrence = dueDate == nil ? nil : recurrence
        self.recurrenceDay = recurrenceDay
        self.seriesID = seriesID
        self.occurrence = occurrence
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.deletedAt = deletedAt
    }

    var recordName: String { Self.recordName(id) }

    static func recordName(_ id: String) -> String { "task." + id }

    // The id in a `task.<id>` record name, when it's a valid one.
    static func id(recordName: String) -> String? {
        guard recordName.hasPrefix("task.") else { return nil }
        let id = String(recordName.dropFirst(5))
        return isValidID(id) ? id : nil
    }

    static func isValidID(_ id: String) -> Bool {
        (1...200).contains(id.count) && id.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == ".")
        }
    }

    var isDeleted: Bool { deletedAt != nil }
    var isCompleted: Bool { completedAt != nil }
    var isOpen: Bool { !isDeleted && !isCompleted }
    var isRecurring: Bool { recurrence != nil && dueDate != nil }

    // The display title and note: the title's @time removed, and whatever follows its
    // first sentence-ending period joined with `notes`.
    var parts: TaskTitle.Parts { TaskTitle.parts(title: title, notes: notes) }

    // Minutes after midnight from the title's @time.
    var timeMinutes: Int? { TaskTime.minutes(in: title) }
}

// What a sync merge keeps together (docs/sync-schema.md, "Fields and intentions").
enum FieldGroup: String, Codable, CaseIterable, Sendable {
    case content, schedule, done, removed
}

extension JuiceTask {
    mutating func copy(_ group: FieldGroup, from other: JuiceTask) {
        switch group {
        case .content:
            title = other.title
            notes = other.notes
        case .schedule:
            dueDate = other.dueDate
            recurrence = other.recurrence
            recurrenceDay = other.recurrenceDay
            seriesID = other.seriesID
            occurrence = other.occurrence
        case .done:
            completedAt = other.completedAt
        case .removed:
            deletedAt = other.deletedAt
        }
    }
}
