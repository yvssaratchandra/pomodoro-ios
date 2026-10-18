import XCTest
import ActivityKit
@testable import PomodoroNative

final class NativeIntegrationTests: XCTestCase {
    func testSignedGroupResolutionReportsAccessFailureAndRetries() {
        let group = "group.com.example.Pomodoro.Native"
        let permissions = SignedAppGroups(groups: [group + ".ABCDE12345"], teamID: "ABCDE12345")
        let failure = SharedWidgetContainer.resolve(configured: group, signing: .success(permissions), container: { _ in nil })
        XCTAssertNil(failure.directory)
        XCTAssertNotNil(failure.failure)
        XCTAssertEqual(failure.selectedGroup, group + ".ABCDE12345")
        let directory = URL(fileURLWithPath: "/shared-test")
        let retry = SharedWidgetContainer.resolve(configured: group, signing: .success(permissions), container: { selected in
            XCTAssertEqual(selected, group + ".ABCDE12345")
            return directory
        })
        XCTAssertEqual(retry.directory, directory)
        XCTAssertNil(retry.failure)
    }

    func testUndeclaredGroupNeverAttemptsContainerAccess() {
        let result = SharedWidgetContainer.resolve(configured: "group.expected",
            signing: .success(SignedAppGroups(groups: ["group.unrelated"], teamID: nil)), container: { _ in
                XCTFail("Must not access an unrelated or undeclared group")
                return nil
            })
        XCTAssertNil(result.selectedGroup)
        XCTAssertNil(result.directory)
        XCTAssertNotNil(result.failure)
    }

    func testNativeMetadataAndPrivacyPayload() throws {
        for sound in CompletionSound.allCases where sound.filename != nil {
            XCTAssertNotNil(Bundle.main.url(forResource: sound.rawValue, withExtension: "wav"))
        }
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
