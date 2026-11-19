import XCTest
@testable import JuiceCore

// Mirrors the website's taskTime, taskTitle and dateWords tests.
final class TaskTextTests: XCTestCase {
    func testTimeLabels() {
        let cases = [("Call dentist @2", "2 pm"), ("Standup @930", "9:30 am"), ("Lunch @12", "12 pm"),
                     ("Gym @6am", "6 am"), ("Dinner @7:15pm", "7:15 pm"), ("Movie @530", "5:30 pm"),
                     ("Dentist @9am. Bring the card", "9 am")]
        for (title, expected) in cases { XCTAssertEqual(TaskTime.label(for: title), expected, title) }
        XCTAssertNil(TaskTime.label(for: "Water plants"))
    }

    func testNotTimes() {
        for title in ["Email bob@123.com", "Ping @99", "Ping @12:75", "Read @2nd chapter"] {
            XCTAssertNil(TaskTime.label(for: title), title)
            XCTAssertEqual(TaskTime.strip(title), title)
        }
        XCTAssertEqual(TaskTime.strip("Call @2 dentist"), "Call dentist")
    }

    func testSortsByTimeThenTitle() {
        let titles = ["Buy milk", "Call bank @2pm", "Apples", "Dentist @9:30am"]
        XCTAssertEqual(titles.sorted(by: TaskTime.compare), ["Dentist @9:30am", "Call bank @2pm", "Apples", "Buy milk"])
    }

    func testSplitsTitleAndNote() {
        let cases = [("Pay $12.50", "Pay $12.50", ""), ("Check juice.tinyk.ing", "Check juice.tinyk.ing", ""),
                     ("See Dr. Smith", "See Dr. Smith", ""), ("See Dr. Smith. Bring forms", "See Dr. Smith", "Bring forms"),
                     ("Buy milk. Oat if they have it", "Buy milk", "Oat if they have it"), ("Buy milk.", "Buy milk", "")]
        for (value, title, note) in cases {
            let split = TaskTitle.split(value)
            XCTAssertEqual(split.title, title, value)
            XCTAssertEqual(split.note, note, value)
        }
    }

    func testParts() {
        XCTAssertEqual(TaskTitle.parts(title: "Dentist @9:30am. Bring the card", notes: ""), .init(title: "Dentist", note: "Bring the card"))
        XCTAssertEqual(TaskTitle.parts(title: "Email bob@123.com", notes: ""), .init(title: "Email bob@123.com", note: ""))
        XCTAssertEqual(TaskTitle.parts(title: "Call bank. Ask about fees", notes: "Account 42"),
                       .init(title: "Call bank", note: "Ask about fees\nAccount 42"))
    }

    // Thursday, Nov 19 2026.
    let today = day("2026-11-19")

    func testDateWords() {
        XCTAssertNil(DateWords.find(in: "Plan launch someday", today: today))
        for title in ["Buy sun cream", "Sat down with Alex", "Prep for tomorrow's meeting", "Review today’s notes"] {
            XCTAssertNil(DateWords.find(in: title, today: today), title)
        }
        XCTAssertEqual(DateWords.find(in: "Call mom sunday", today: today)?.date, day("2026-11-22"))
        XCTAssertEqual(DateWords.find(in: "Pay rent tomorrow", today: today)?.date, day("2026-11-20"))
        XCTAssertEqual(DateWords.find(in: "Standup thursday", today: today)?.date, today)
        XCTAssertEqual(DateWords.find(in: "Standup next thursday", today: today)?.date, day("2026-11-26"))
        XCTAssertEqual(DateWords.find(in: "Plan next week", today: today)?.date, day("2026-11-23"))
        XCTAssertEqual(DateWords.find(in: "Bills next month", today: today)?.date, day("2026-12-01"))
        XCTAssertEqual(DateWords.find(in: "Party Dec 3rd", today: today)?.date, day("2026-12-03"))
        XCTAssertEqual(DateWords.find(in: "Taxes april 15", today: today)?.date, day("2027-04-15"))
        XCTAssertEqual(DateWords.find(in: "Trip 2 feb 2028", today: today)?.date, day("2028-02-02"))
        XCTAssertEqual(DateWords.find(in: "Thing feb 31", today: today)?.date, day("2027-02-28"))
        XCTAssertNil(DateWords.findInTitle("Book flights. Leave friday", today: today))
        XCTAssertEqual(DateWords.findInTitle("Book flights friday. Window seat", today: today)?.word, "friday")
    }

    func testDraft() {
        let draft = TaskDraft(text: "Call mom tomorrow @5pm", today: today)
        XCTAssertEqual(draft.title, "Call mom @5pm")
        XCTAssertEqual(draft.dueDate, day("2026-11-20"))
        XCTAssertEqual(TaskDraft(text: "Water plants", today: today).dueDate, today)
        XCTAssertNil(TaskDraft(text: "Water plants", today: today, undatedIfNoDate: true).dueDate)
        // A given date wins; the word still leaves the title.
        let given = TaskDraft(text: "Pay rent friday", dueDate: day("2026-12-01"), today: today)
        XCTAssertEqual(given.title, "Pay rent")
        XCTAssertEqual(given.dueDate, day("2026-12-01"))
        // A title that's only a date word stays as typed.
        XCTAssertEqual(TaskDraft(text: "Tomorrow", today: today).title, "Tomorrow")
        XCTAssertTrue(TaskDraft(text: "   ", today: today).isEmpty)
    }
}
