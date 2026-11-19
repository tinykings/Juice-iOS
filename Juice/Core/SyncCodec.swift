import Foundation

// The JuiceTask record's fields (docs/sync-schema.md), without CloudKit: CloudSync copies
// these into a CKRecord, and the website writes the same names.
enum SyncCodec {
    static let recordType = "JuiceTask"
    static let zoneName = "JuiceSync"
    static let schemaVersion = 1

    static let maxTitle = 1000
    static let maxNotes = 10_000

    enum Value: Equatable, Sendable {
        case string(String)
        case int(Int64)

        var string: String? { if case .string(let value) = self { value } else { nil } }
        var int: Int64? { if case .int(let value) = self { value } else { nil } }
    }

    // MARK: Times

    private static let isoOut: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private static let isoPattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$"#

    // `2026-11-19T22:04:05.123Z`, as the web writes it.
    static func iso(_ date: Date) -> String { isoOut.string(from: date) }

    static func date(_ string: String) -> Date? {
        guard string.range(of: isoPattern, options: .regularExpression) != nil else { return nil }
        return isoOut.date(from: string) ?? isoPlain.date(from: string)
    }

    // An ISO time in the canonical form, or nil for empty or malformed values.
    static func cleanTime(_ value: String?) -> String? {
        value.flatMap(date).map(iso)
    }

    // MARK: Records

    static func fields(_ task: JuiceTask) -> [String: Value] {
        [
            "title": .string(task.title),
            "notes": .string(task.notes),
            "dueDate": .string(task.dueDate?.description ?? ""),
            "recurrence": .string(task.isRecurring ? task.recurrence!.rawValue : ""),
            "recurrenceDay": .int(Int64(task.recurrenceDay ?? 0)),
            "seriesID": .string(task.seriesID ?? ""),
            "occurrence": .int(Int64(task.occurrence)),
            "createdAt": .string(task.createdAt),
            "completedAt": .string(task.completedAt ?? ""),
            "deletedAt": .string(task.deletedAt ?? ""),
            "schemaVersion": .int(Int64(schemaVersion)),
        ]
    }

    // A JuiceTask record's fields; nil when it's not one Juice understands, including a
    // newer schemaVersion, which is left alone rather than misread.
    static func decode(recordName: String, fields: [String: Value]) -> JuiceTask? {
        guard let version = fields["schemaVersion"]?.int, version <= schemaVersion,
              let id = JuiceTask.id(recordName: recordName),
              let title = fields["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty, title.count <= maxTitle,
              let createdAt = cleanTime(fields["createdAt"]?.string) else { return nil }
        let notes = String((fields["notes"]?.string ?? "").prefix(maxNotes))
        let due = fields["dueDate"]?.string.flatMap(CalendarDay.init)
        let recurrence = due == nil ? nil : fields["recurrence"]?.string.flatMap(Recurrence.init(rawValue:))
        let anchor = Int(clamping: fields["recurrenceDay"]?.int ?? 0)
        let series = fields["seriesID"]?.string.flatMap { JuiceTask.isValidID($0) ? $0 : nil }
        let occurrence = Int(clamping: fields["occurrence"]?.int ?? 0)
        return JuiceTask(
            id: id, title: title, notes: notes, dueDate: due, recurrence: recurrence,
            recurrenceDay: (29...31).contains(anchor) ? anchor : nil, seriesID: series,
            occurrence: max(0, occurrence), createdAt: createdAt,
            completedAt: cleanTime(fields["completedAt"]?.string),
            deletedAt: cleanTime(fields["deletedAt"]?.string))
    }
}
