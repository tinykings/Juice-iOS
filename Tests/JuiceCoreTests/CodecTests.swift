import XCTest
@testable import JuiceCore

final class CodecTests: XCTestCase {
    func testRoundTrip() {
        let task = JuiceTask(id: "rent.3", title: "Pay rent @9am", notes: "Online", dueDate: day("2026-11-30"),
                             recurrence: .monthly, recurrenceDay: 31, seriesID: "rent", occurrence: 3,
                             createdAt: "2026-10-31T13:00:00.000Z", completedAt: "2026-11-19T14:05:00.123Z")
        XCTAssertEqual(SyncCodec.decode(recordName: task.recordName, fields: SyncCodec.fields(task)), task)
    }

    func testRejectsWhatItCantRead() {
        var fields = SyncCodec.fields(JuiceTask(id: "a", title: "A", createdAt: "2026-11-19T14:05:00.000Z"))
        XCTAssertNil(SyncCodec.decode(recordName: "item.a", fields: fields))
        XCTAssertNil(SyncCodec.decode(recordName: "task.", fields: fields))
        fields["schemaVersion"] = .int(2)
        XCTAssertNil(SyncCodec.decode(recordName: "task.a", fields: fields))
        fields["schemaVersion"] = .int(1)
        fields["title"] = .string("   ")
        XCTAssertNil(SyncCodec.decode(recordName: "task.a", fields: fields))
    }

    func testCleansFields() {
        let fields: [String: SyncCodec.Value] = [
            "title": .string(" Walk "), "dueDate": .string(""), "recurrence": .string("daily"),
            "recurrenceDay": .int(12), "createdAt": .string("2026-11-19T14:05:00Z"),
            "completedAt": .string("yesterday"), "seriesID": .string("bad id"), "schemaVersion": .int(1),
        ]
        let task = SyncCodec.decode(recordName: "task.a", fields: fields)
        XCTAssertEqual(task?.title, "Walk")
        XCTAssertNil(task?.recurrence, "no repeat without a date")
        XCTAssertNil(task?.recurrenceDay)
        XCTAssertNil(task?.completedAt)
        XCTAssertNil(task?.seriesID)
        XCTAssertEqual(task?.createdAt, "2026-11-19T14:05:00.000Z")
    }
}
