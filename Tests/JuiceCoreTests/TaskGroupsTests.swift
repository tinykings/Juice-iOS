import XCTest
@testable import JuiceCore

final class TaskGroupsTests: XCTestCase {
    let today = day("2026-11-19")

    func task(_ id: String, _ title: String, _ due: String?) -> JuiceTask {
        JuiceTask(id: id, title: title, dueDate: due.map(day), createdAt: "2026-11-01T00:00:00.000Z")
    }

    func testGroups() {
        let tasks = [task("a", "Old", "2026-11-01"), task("b", "Undated", nil), task("c", "Late @5pm", "2026-11-19"),
                     task("d", "Early @8am", "2026-11-19"), task("e", "Soon", "2026-11-26"), task("f", "Later", "2027-01-04"),
                     task("g", "Dec", "2026-12-15")]
        let event = CalendarEvent(id: "ev", title: "Meeting", date: today, allDay: false, start: utc(2026, 11, 19, 15))
        let groups = TaskGroups.build(open: tasks, events: [event], today: today)
        XCTAssertEqual(groups.map(\.label), ["Overdue", "Today", "Tomorrow", "Saturday", "Sunday", "Monday", "Tuesday",
                                             "Wednesday", "Thursday", "December 2026", "January 2027"])
        XCTAssertEqual(groups[0].items.map(\.id), ["task:a", "task:b"])
        XCTAssertEqual(groups[1].items.map(\.id), ["task:d", "task:c", "event:ev"])
        XCTAssertEqual(groups[1].detail, "Thu, Nov 19")
        XCTAssertTrue(groups[1].isToday)
        XCTAssertEqual(groups[8].items.map(\.id), ["task:e"])
        XCTAssertEqual(groups[8].detail, "Nov 26")
        XCTAssertEqual(TaskGroups.dateLabel(tasks[0], in: groups[0], today: today), "Nov 1")
        XCTAssertEqual(TaskGroups.dateLabel(tasks[1], in: groups[0], today: today), "No date")
        XCTAssertEqual(TaskGroups.dateLabel(tasks[5], in: groups[10], today: today), "Mon, Jan 4")
        XCTAssertNil(TaskGroups.dateLabel(tasks[2], in: groups[1], today: today))
    }

    func testNoOverdueGroupWhenNothingIsLate() {
        XCTAssertEqual(TaskGroups.build(open: [], today: today).first?.label, "Today")
    }
}
