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
    func testUnicodePreviewsStayWithinActivityPayloadBudgetWithoutChangingSavedText() throws {
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 280)
        var state = AppSnapshot(projects: [Project(name: String(text.prefix(100)))])
        try TimerEngine.startFocus(&state, projectID: state.projects[0].id, minutes: 25, intention: text, now: Date())
        state.settings.showProjectNameOnLockScreen = true
        state.settings.showIntentionOnLockScreen = true
        let projection = try XCTUnwrap(LiveActivityProjection(state: state))
        XCTAssertLessThan(try JSONEncoder().encode(projection).count, 4096)
        XCTAssertEqual(state.activeTimer?.intention, text)
        XCTAssertTrue(projection.intention?.hasSuffix("…") == true)
    }

}
