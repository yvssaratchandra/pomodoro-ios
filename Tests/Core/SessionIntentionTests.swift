import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class SessionIntentionTests: XCTestCase {
    func testNormalizationAndLifecycle() throws {
        XCTAssertNil(try SessionText.normalize("  \n"))
        XCTAssertEqual(try SessionText.normalize("  Write chapter  \n"), "Write chapter")
        XCTAssertThrowsError(try SessionText.normalize(String(repeating: "a", count: 281)))
        var state = AppSnapshot(projects: [Project(name: "Writing")])
        let now = Date()
        try TimerEngine.startFocus(&state, projectID: state.projects[0].id, minutes: 10, intention: "  Write chapter  ", now: now)
        XCTAssertEqual(state.activeTimer?.intention, "Write chapter")
        TimerEngine.finish(&state, now: now.addingTimeInterval(30), force: true)
        XCTAssertEqual(state.sessions.first?.intention, "Write chapter")
        XCTAssertEqual(try BackupService.decode(BackupService.encode(state)), state)
    }
}

final class SessionPlanTextTests: XCTestCase {
    func testParsingLinesPreservesWordsAndPunctuation() {
        XCTAssertEqual(SessionPlanText.items(from: "  Draft, revise; publish.\r\n\r\n Research\r Check references\n"),
                       ["Draft, revise; publish.", "Research", "Check references"])
        XCTAssertEqual(SessionPlanText.items(from: "  研究 🧠 \n"), ["研究 🧠"])
        XCTAssertTrue(SessionPlanText.items(from: nil).isEmpty)
        XCTAssertTrue(SessionPlanText.items(from: " \t\r\n ").isEmpty)
    }

    func testSerializationTrimsEmptyTasksAndCountsSeparators() throws {
        XCTAssertNil(try SessionPlanText.serialize(["", " \n "]))
        XCTAssertEqual(try SessionPlanText.serialize([" Draft ", "", " Research "]), "Draft\nResearch")
        XCTAssertEqual(try SessionPlanText.serialize([String(repeating: "a", count: 139), String(repeating: "🧠", count: 140)])?.count, 280)
        XCTAssertThrowsError(try SessionPlanText.serialize([String(repeating: "a", count: 140), String(repeating: "b", count: 140)]))
    }

    func testMultilinePlanSurvivesTimerLifecycleAndBackup() throws {
        let plan = try SessionPlanText.serialize(["Draft introduction", "Find two supporting references"])
        var state = AppSnapshot(projects: [Project(name: "Writing")])
        let now = Date()
        try TimerEngine.startFocus(&state, projectID: state.projects[0].id, minutes: 10, intention: plan, now: now)
        XCTAssertEqual(state.activeTimer?.intention, plan)
        TimerEngine.finish(&state, now: now.addingTimeInterval(30), force: true)
        let restored = try BackupService.decode(BackupService.encode(state))
        XCTAssertEqual(restored.sessions.first?.intention, plan)
        XCTAssertEqual(SessionPlanText.items(from: restored.sessions.first?.intention), ["Draft introduction", "Find two supporting references"])
    }
}
