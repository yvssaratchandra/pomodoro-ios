import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class WidgetSnapshotFileTests: XCTestCase {
    func testSnapshotReplacementAndCorruptOrUnknownVersionFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(WidgetSnapshotFile.read(in: directory))
        var state = AppSnapshot(projects: [Project(name: "Writing")])
        let first = WidgetSnapshot(state: state, now: Date())
        try WidgetSnapshotFile.write(first, in: directory)
        XCTAssertEqual(WidgetSnapshotFile.read(in: directory), first)
        state.projects[0].name = "Updated"
        let second = WidgetSnapshot(state: state, now: Date())
        try WidgetSnapshotFile.write(second, in: directory)
        XCTAssertEqual(WidgetSnapshotFile.read(in: directory), second)
        let url = directory.appendingPathComponent(WidgetSnapshotFile.filename)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(second)) as? [String: Any])
        json["formatVersion"] = 999
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        XCTAssertNil(WidgetSnapshotFile.read(in: directory))
        json["formatVersion"] = 1
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        XCTAssertNil(WidgetSnapshotFile.read(in: directory))
        try Data("partial JSON".utf8).write(to: url)
        XCTAssertNil(WidgetSnapshotFile.read(in: directory))
    }

    func testSummaryRoundTripAndInvalidSummaryFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 0)
        let summary = WidgetSnapshot.SavedFocus(dayStart: now, dayEnd: now.addingTimeInterval(86400),
            timeZoneIdentifier: "GMT", seconds: 123.5)
        let snapshot = WidgetSnapshot(state: AppSnapshot(), now: now, savedFocus: summary)
        try WidgetSnapshotFile.write(snapshot, in: directory)
        XCTAssertEqual(WidgetSnapshotFile.read(in: directory), snapshot)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        var savedFocus = try XCTUnwrap(json["savedFocus"] as? [String: Any])
        savedFocus["seconds"] = -1
        json["savedFocus"] = savedFocus
        try JSONSerialization.data(withJSONObject: json).write(to: directory.appendingPathComponent(WidgetSnapshotFile.filename))
        XCTAssertNil(WidgetSnapshotFile.read(in: directory))
    }
}
