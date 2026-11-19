import XCTest
@testable import JuiceCore

final class TaskLibraryTests: XCTestCase {
    let now = local(2026, 11, 19, 9)
    var today: CalendarDay { .today(now, calendar: testCalendar) }

    func add(_ library: inout TaskLibrary, _ text: String, recurrence: Recurrence? = nil, id: String) -> JuiceTask {
        library.add(TaskDraft(text: text, today: today), recurrence: recurrence, id: id, now: now)!
    }

    func testAddWritesEveryGroup() {
        var library = TaskLibrary()
        let task = add(&library, "Call mom tomorrow", id: "a")
        XCTAssertEqual(task.title, "Call mom")
        XCTAssertEqual(task.dueDate, day("2026-11-20"))
        XCTAssertEqual(library.dirty["task.a"]?.fields, Set(FieldGroup.allCases))
        XCTAssertNil(library.add(TaskDraft(text: "Dup", today: today), id: "a", now: now))
        XCTAssertNil(library.add(TaskDraft(text: "Bad id", today: today), id: "a/b", now: now))
    }

    func testUpdateMarksOnlyChangedGroups() {
        var library = TaskLibrary()
        _ = add(&library, "Water plants", recurrence: .monthly, id: "a")
        library.pushSucceeded(recordName: "task.a", rev: library.rev, systemFields: Data([1]))
        library.update("a", title: "Water plants", notes: "", dueDate: today, recurrence: .monthly)
        XCTAssertNil(library.dirty["task.a"], "nothing changed")
        library.update("a", title: "Water ferns", notes: "", dueDate: today, recurrence: .monthly)
        XCTAssertEqual(library.dirty["task.a"]?.fields, [.content])
        library.reschedule("a", to: day("2026-11-30"))
        XCTAssertEqual(library.dirty["task.a"]?.fields, [.content, .schedule])
        // Undated tasks don't repeat.
        library.update("a", title: "Water ferns", notes: "", dueDate: nil, recurrence: .monthly)
        XCTAssertNil(library.task("a")?.recurrence)
    }

    func testCompletingARecurringTaskMakesTheNextOccurrence() {
        var library = TaskLibrary()
        var task = add(&library, "Pay rent", recurrence: .monthly, id: "rent")
        task.dueDate = day("2026-10-31")
        library.entries[task.recordName] = task
        let next = library.complete("rent", now: now, calendar: testCalendar)
        XCTAssertEqual(next?.id, "rent.1")
        XCTAssertEqual(next?.dueDate, day("2026-11-30"))
        XCTAssertEqual(next?.recurrenceDay, 31)
        XCTAssertEqual(next?.seriesID, "rent")
        XCTAssertEqual(library.task("rent")?.seriesID, "rent")
        XCTAssertTrue(library.task("rent")!.isCompleted)

        let after = library.complete("rent.1", now: local(2026, 11, 30, 8), calendar: testCalendar)
        XCTAssertEqual(after?.id, "rent.2")
        XCTAssertEqual(after?.dueDate, day("2026-12-31"))
        XCTAssertEqual(library.completedToday(now: local(2026, 11, 30, 9), calendar: testCalendar).map(\.id), ["rent.1"])
    }

    func testUncompleteRemovesTheUntouchedOccurrenceAndCompletingAgainRevivesIt() {
        var library = TaskLibrary()
        _ = add(&library, "Gym", recurrence: .daily, id: "gym")
        library.complete("gym", now: now, calendar: testCalendar)
        library.uncomplete("gym", now: now)
        XCTAssertTrue(library.task("gym")!.isOpen)
        XCTAssertTrue(library.task("gym.1")!.isDeleted)
        XCTAssertEqual(library.openTasks.map(\.id), ["gym"])
        let again = library.complete("gym", now: now, calendar: testCalendar)
        XCTAssertEqual(again?.id, "gym.1")
        XCTAssertTrue(library.task("gym.1")!.isOpen)
    }

    func testCompletingDoesntReopenAnOccurrenceAlreadyMade() {
        var library = TaskLibrary()
        _ = add(&library, "Gym", recurrence: .daily, id: "gym")
        library.complete("gym", now: now, calendar: testCalendar)
        library.complete("gym.1", now: now, calendar: testCalendar)
        library.uncomplete("gym", now: now) // gym.1 is done, so it stays.
        library.complete("gym", now: now, calendar: testCalendar)
        XCTAssertTrue(library.task("gym.1")!.isCompleted)
    }

    func testRemoteMergeKeepsPendingGroups() {
        var library = TaskLibrary()
        _ = add(&library, "Buy milk", id: "m")
        library.pushSucceeded(recordName: "task.m", rev: library.rev, systemFields: Data([1]))
        library.update("m", title: "Buy oat milk", notes: "", dueDate: today, recurrence: nil)
        let pushedRev = library.rev

        // Another device deleted it meanwhile.
        var remote = library.task("m")!
        remote.title = "Buy milk"
        remote.deletedAt = "2026-11-19T15:00:00.000Z"
        library.pushConflicted(recordName: "task.m")
        library.applyRemote(recordName: "task.m", task: remote, systemFields: Data([2]))
        let merged = library.task("m")!
        XCTAssertEqual(merged.title, "Buy oat milk", "the pending edit is kept")
        XCTAssertTrue(merged.isDeleted, "the remote delete is taken")
        XCTAssertEqual(library.pending.map(\.rev), [pushedRev])
        library.pushSucceeded(recordName: "task.m", rev: pushedRev, systemFields: Data([3]))
        XCTAssertEqual(library.pendingCount, 0)
        XCTAssertEqual(library.systemFields["task.m"], Data([3]))
    }

    func testPushOnlyClearsTheRevisionItSent() {
        var library = TaskLibrary()
        _ = add(&library, "A", id: "a")
        let sent = library.rev
        library.update("a", title: "B", notes: "", dueDate: today, recurrence: nil)
        library.pushSucceeded(recordName: "task.a", rev: sent, systemFields: nil)
        XCTAssertEqual(library.pendingCount, 1)
    }

    func testImportYieldsToRemote() {
        var library = TaskLibrary()
        let local = JuiceTask(id: "x", title: "Local", dueDate: today, createdAt: "2026-11-19T10:00:00.000Z")
        var gone = local; gone.id = "y"; gone.deletedAt = "2026-11-19T10:00:00.000Z"
        XCTAssertEqual(library.importTasks([local, gone]), 1)
        var remote = local; remote.title = "Remote"
        library.applyRemote(recordName: "task.x", task: remote, systemFields: Data([1]))
        XCTAssertEqual(library.task("x")?.title, "Remote")
        XCTAssertEqual(library.pendingCount, 0)
    }

    func testRemoteDeletionAndPurge() {
        var library = TaskLibrary()
        _ = add(&library, "Old", id: "old")
        library.complete("old", now: now, calendar: testCalendar)
        library.pushSucceeded(recordName: "task.old", rev: library.rev, systemFields: Data([1]))
        XCTAssertEqual(library.purgeable(now: now.addingTimeInterval(29 * 86_400)), [])
        XCTAssertEqual(library.purgeable(now: now.addingTimeInterval(31 * 86_400)), ["task.old"])
        library.applyRemoteDeletion(recordName: "task.old")
        XCTAssertNil(library.task("old"))

        // A pending change survives a remote delete and is created again.
        _ = add(&library, "Keep", id: "keep")
        library.applyRemoteDeletion(recordName: "task.keep")
        XCTAssertNotNil(library.task("keep"))
        XCTAssertNil(library.systemFields["task.keep"])
    }

    func testRoundTripsThroughJSON() throws {
        var library = TaskLibrary()
        _ = add(&library, "Gym @6am", recurrence: .weekly, id: "gym")
        library.complete("gym", now: now, calendar: testCalendar)
        let decoded = try JSONDecoder().decode(TaskLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded, library)
    }
}
