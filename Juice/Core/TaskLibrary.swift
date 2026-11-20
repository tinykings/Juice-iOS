import Foundation

// The tasks as synced through the JuiceSync zone (docs/sync-schema.md): one entry per
// task, tombstones included, plus the pending local intentions. Plain values only;
// CloudSync does the CloudKit requests. Follows [void]'s SyncLibrary.
//
// Local intentions are dirty marks, stored with the library so they survive being
// offline and relaunches, and coalesce per task. Each mark records the library's `rev`
// when it was made; a push clears it only if nothing changed the task again while the
// push was in flight.
//
// - The last accepted intention wins, per field group: a pending change is written again
//   over a newer remote revision, keeping the remote's other fields.
// - Deleting writes a tombstone (`deletedAt`). Old tombstones and old completed tasks
//   are purged (really deleted) after `purgeAfterDays`.
// - An import (tasks from before sync was on) never overwrites a remote record or tombstone.
struct TaskLibrary: Codable, Equatable, Sendable {
    static let purgeAfterDays = 30

    enum Mode: String, Codable, Sendable { case set, `import` }

    struct Mark: Codable, Equatable, Sendable {
        var rev: Int
        var mode: Mode
        var fields: Set<FieldGroup>

        init(rev: Int, mode: Mode, fields: Set<FieldGroup>) {
            self.rev = rev
            self.mode = mode
            self.fields = fields
        }

        // Field groups from a newer version this one doesn't know are dropped rather than
        // failing to load the library.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rev = try c.decode(Int.self, forKey: .rev)
            mode = try c.decode(Mode.self, forKey: .mode)
            fields = Set(try c.decode([String].self, forKey: .fields).compactMap(FieldGroup.init(rawValue:)))
        }
    }

    // recordName -> its latest state, tombstones included.
    var entries: [String: JuiceTask] = [:]
    var dirty: [String: Mark] = [:]
    var rev = 0
    // An archived CKServerChangeToken (iOS) for the JuiceSync zone.
    var changeToken: Data?
    var zoneReady = false
    // recordName -> the record's archived CloudKit system fields (its change tag).
    var systemFields: [String: Data] = [:]
    var lastSync: Date?

    init() {}

    var pendingCount: Int { dirty.count }

    func task(_ id: String) -> JuiceTask? { entries[JuiceTask.recordName(id)] }

    var openTasks: [JuiceTask] { entries.values.filter(\.isOpen) }

    // Completed since local midnight today, most recent first.
    func completedToday(now: Date = Date(), calendar: Calendar = .current) -> [JuiceTask] {
        let start = CalendarDay.today(now, calendar: calendar).start(in: calendar)
        return entries.values
            .compactMap { task -> (JuiceTask, Date)? in
                guard !task.isDeleted, let done = task.completedAt.flatMap(SyncCodec.date), done >= start else { return nil }
                return (task, done)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // The tasks with pending intentions, for a push.
    var pending: [(recordName: String, rev: Int)] {
        dirty.compactMap { name, mark in entries[name] == nil ? nil : (name, mark.rev) }
            .sorted { $0.recordName < $1.recordName }
    }

    // MARK: Local changes

    private mutating func write(_ task: JuiceTask, _ fields: Set<FieldGroup>) {
        rev += 1
        let name = task.recordName
        entries[name] = task
        var mark = dirty[name].flatMap { $0.mode == .set ? $0 : nil } ?? Mark(rev: rev, mode: .set, fields: [])
        mark.rev = rev
        mark.fields.formUnion(fields)
        dirty[name] = mark
    }

    @discardableResult
    mutating func add(_ draft: TaskDraft, recurrence: Recurrence? = nil, id: String = UUID().uuidString.lowercased(),
                      now: Date = Date()) -> JuiceTask? {
        guard !draft.isEmpty, JuiceTask.isValidID(id), entries[JuiceTask.recordName(id)] == nil else { return nil }
        let task = JuiceTask(id: id, title: draft.title, notes: draft.notes, dueDate: draft.dueDate,
                             recurrence: recurrence, createdAt: SyncCodec.iso(now))
        write(task, Set(FieldGroup.allCases))
        return task
    }

    // Writes only the groups that changed. A task moved to another day drops its
    // remembered day: the series starts over from the new date.
    mutating func update(_ id: String, title: String, notes: String, dueDate: CalendarDay?, recurrence: Recurrence?) {
        guard var task = task(id), !task.isDeleted else { return }
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SyncCodec.maxTitle))
        guard !title.isEmpty else { return }
        var groups: Set<FieldGroup> = []
        let notes = String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SyncCodec.maxNotes))
        if task.title != title || task.notes != notes {
            task.title = title
            task.notes = notes
            groups.insert(.content)
        }
        let repeatRule = dueDate == nil ? nil : recurrence
        if task.dueDate != dueDate || task.recurrence != repeatRule {
            if task.dueDate != dueDate { task.recurrenceDay = nil }
            task.dueDate = dueDate
            task.recurrence = repeatRule
            groups.insert(.schedule)
        }
        guard !groups.isEmpty else { return }
        write(task, groups)
    }

    mutating func reschedule(_ id: String, to date: CalendarDay?) {
        guard let task = task(id) else { return }
        update(id, title: task.title, notes: task.notes, dueDate: date, recurrence: task.recurrence)
    }

    // Completes a task. An open recurring task also gets its next occurrence, whose id
    // depends only on the series, so two devices completing the same one agree.
    // Returns the next occurrence, if one was made.
    @discardableResult
    mutating func complete(_ id: String, now: Date = Date(), calendar: Calendar = .current) -> JuiceTask? {
        guard var task = task(id), task.isOpen else { return nil }
        let stamp = SyncCodec.iso(now)
        task.completedAt = stamp
        var groups: Set<FieldGroup> = [.done]
        guard let due = task.dueDate, let recurrence = task.recurrence else {
            write(task, groups)
            return nil
        }
        let series = task.seriesID ?? task.id
        if task.seriesID == nil {
            task.seriesID = series
            groups.insert(.schedule)
        }
        write(task, groups)

        let anchor = recurrence.usesAnchorDay ? RecurrenceRules.anchorDay(due, recurrenceDay: task.recurrenceDay) : nil
        let nextDate = RecurrenceRules.nextAfterCompletion(due, recurrence, today: .today(now, calendar: calendar), anchorDay: anchor)
        let nextID = "\(series).\(task.occurrence + 1)"
        guard JuiceTask.isValidID(nextID) else { return nil }
        // Already made, here or on another device; only a deleted one is made again.
        if let existing = self.task(nextID), !existing.isDeleted { return existing }
        let next = JuiceTask(id: nextID, title: task.title, notes: task.notes, dueDate: nextDate,
                             recurrence: recurrence, recurrenceDay: (anchor ?? 0) > 28 ? anchor : nil,
                             seriesID: series, occurrence: task.occurrence + 1, createdAt: stamp)
        write(next, Set(FieldGroup.allCases))
        return next
    }

    // Reopens a completed task, and deletes the occurrence completing it made if that's
    // still open and unchanged in title.
    mutating func uncomplete(_ id: String, now: Date = Date()) {
        guard var task = task(id), task.isCompleted, !task.isDeleted else { return }
        if let series = task.seriesID, task.recurrence != nil,
           let next = self.task("\(series).\(task.occurrence + 1)"), next.isOpen, next.title == task.title {
            delete(next.id, now: now)
        }
        task.completedAt = nil
        write(task, [.done])
    }

    mutating func delete(_ id: String, now: Date = Date()) {
        guard var task = task(id), !task.isDeleted else { return }
        task.deletedAt = SyncCodec.iso(now)
        write(task, [.removed])
    }

    // Undo for `delete`.
    mutating func restore(_ id: String) {
        guard var task = task(id), task.isDeleted else { return }
        task.deletedAt = nil
        write(task, [.removed])
    }

    // Every overdue open task moves to today, keeping its repeat.
    mutating func moveOverdue(to today: CalendarDay) {
        for task in openTasks {
            guard let due = task.dueDate, due < today else { continue }
            reschedule(task.id, to: today)
        }
    }

    // Offers tasks from outside sync (this device before sync was on). Only tasks the
    // library has no record of are added, and a remote copy found later wins.
    @discardableResult
    mutating func importTasks(_ tasks: [JuiceTask]) -> Int {
        var added = 0
        for task in tasks where entries[task.recordName] == nil && !task.isDeleted {
            if added == 0 { rev += 1 }
            added += 1
            entries[task.recordName] = task
            dirty[task.recordName] = Mark(rev: rev, mode: .import, fields: Set(FieldGroup.allCases))
        }
        return added
    }

    // MARK: Clean-up

    // Records to delete for real: tombstones and completed tasks older than
    // `purgeAfterDays`, with nothing pending.
    func purgeable(now: Date = Date()) -> [String] {
        let cutoff = now.addingTimeInterval(-Double(Self.purgeAfterDays) * 86_400)
        return entries.compactMap { name, task in
            guard dirty[name] == nil, systemFields[name] != nil,
                  let ended = (task.deletedAt ?? task.completedAt).flatMap(SyncCodec.date), ended < cutoff else { return nil }
            return name
        }.sorted()
    }

    // Purged here or on another device. A copy with a pending intention is kept, and
    // created again by the next push.
    mutating func applyRemoteDeletion(recordName: String) {
        systemFields[recordName] = nil
        if dirty[recordName] == nil { entries[recordName] = nil }
    }

    // MARK: Remote changes

    // A remote record. `task` is nil when it couldn't be read (or is a newer schema); its
    // revision is still kept so a pending write can succeed.
    mutating func applyRemote(recordName: String, task remote: JuiceTask?, systemFields fields: Data?) {
        if let fields { systemFields[recordName] = fields }
        guard let remote else { return }
        guard let mark = dirty[recordName] else {
            entries[recordName] = remote
            return
        }
        if mark.mode == .import {
            dirty[recordName] = nil
            entries[recordName] = remote
            return
        }
        var merged = remote
        if let local = entries[recordName] {
            for group in mark.fields { merged.copy(group, from: local) }
        }
        entries[recordName] = merged
    }

    mutating func pushSucceeded(recordName: String, rev pushedRev: Int, systemFields fields: Data?) {
        if let fields { systemFields[recordName] = fields }
        if dirty[recordName]?.rev == pushedRev { dirty[recordName] = nil }
    }

    // Another client wrote first. An import yields to it; anything else is written again
    // once the newer revision has been applied.
    mutating func pushConflicted(recordName: String) {
        if dirty[recordName]?.mode == .import { dirty[recordName] = nil }
    }

    // The zone was deleted: every record is created anew, keeping pending intentions.
    mutating func zoneLost() {
        zoneReady = false
        changeToken = nil
        systemFields = [:]
    }
}
