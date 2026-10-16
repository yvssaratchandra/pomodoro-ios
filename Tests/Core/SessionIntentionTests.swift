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
