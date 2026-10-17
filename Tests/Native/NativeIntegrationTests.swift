import XCTest
import ActivityKit
@testable import PomodoroNative

final class NativeIntegrationTests: XCTestCase {
    func testNativeMetadataAndPrivacyPayload() throws {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "PomodoroAppGroup"))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool, true)
        var state = AppSnapshot(projects: [Project(name: "Private project")])
        try TimerEngine.startFocus(&state, projectID: state.projects[0].id, minutes: 10, now: Date())
        let projection = try XCTUnwrap(LiveActivityProjection(state: state))
        let attributes = FocusActivityAttributes(timerID: projection.id)
        XCTAssertEqual(attributes.timerID, state.activeTimer?.id)
        let router = AppURLRouter(scheme: .native)
        let thoughtURL = router.url(for: .captureThought(sessionID: attributes.timerID))
        XCTAssertEqual(router.parse(thoughtURL), .captureThought(sessionID: attributes.timerID))
        XCTAssertNil(projection.projectName)
        XCTAssertNil(projection.intention)
        XCTAssertLessThan(try JSONEncoder().encode(projection).count, 4096)
    }
}
