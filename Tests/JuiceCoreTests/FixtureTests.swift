import XCTest
@testable import JuiceCore

// Tests/fixtures/juice-task-record.json is a JuiceTask record as CloudKit Web Services
// returns it. The website's tests decode the same file.
final class FixtureTests: XCTestCase {
    func testDecodesTheSharedFixture() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/juice-task-record.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let fields = (json["fields"] as! [String: [String: Any]]).compactMapValues { field -> SyncCodec.Value? in
            if let s = field["value"] as? String { return .string(s) }
            if let n = field["value"] as? NSNumber { return .int(n.int64Value) }
            return nil
        }
        let task = try XCTUnwrap(SyncCodec.decode(recordName: json["recordName"] as! String, fields: fields))
        XCTAssertEqual(task.id, "6f1c1d2e-8a3b-4c5d-9e0f-112233445566.2")
        XCTAssertEqual(task.title, "Water plants @9am. Kitchen first")
        XCTAssertEqual(task.dueDate, day("2026-11-21"))
        XCTAssertEqual(task.recurrence, .weekly)
        XCTAssertEqual(task.seriesID, "6f1c1d2e-8a3b-4c5d-9e0f-112233445566")
        XCTAssertEqual(task.occurrence, 2)
        XCTAssertTrue(task.isOpen)
        XCTAssertEqual(task.parts, .init(title: "Water plants", note: "Kitchen first"))
        XCTAssertEqual(task.timeMinutes, 9 * 60)
    }
}
