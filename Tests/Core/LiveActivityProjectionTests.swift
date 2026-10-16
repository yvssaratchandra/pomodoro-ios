import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class LiveActivityProjectionTests: XCTestCase {
    func testPrivateTextIsAbsentFromEncodedPayloadUnlessExplicitlyEnabled() throws {
        var state = AppSnapshot(projects: [Project(name: "Private project")])
        XCTAssertNil(LiveActivityProjection(state: state))
        try TimerEngine.startFocus(&state, projectID: state.projects[0].id, minutes: 25, now: Date())
        state.activeTimer?.intention = "Private intention"
        let hidden = try XCTUnwrap(LiveActivityProjection(state: state))
        XCTAssertNil(hidden.projectName)
        XCTAssertNil(hidden.intention)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(hidden), as: UTF8.self).contains("Private"))
        state.settings.showProjectNameOnLockScreen = true
        XCTAssertEqual(LiveActivityProjection(state: state)?.projectName, "Private project")
        XCTAssertNil(LiveActivityProjection(state: state)?.intention)
        state.settings.showIntentionOnLockScreen = true
        XCTAssertEqual(LiveActivityProjection(state: state)?.intention, "Private intention")
        XCTAssertEqual(LiveActivityProjection(state: state)?.deadline, state.activeTimer?.deadline)
    }
}
