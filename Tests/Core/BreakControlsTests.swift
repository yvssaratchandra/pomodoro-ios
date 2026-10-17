import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class BreakControlsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testDurationEditsOnlyOfferedBreakAndRemembersMatchingProjectPreference() throws {
        for kind in [TimerKind.shortBreak, .longBreak] {
            let project = Project(name: "Writing")
            let offer = BreakOffer(projectID: project.id, kind: kind, minutes: 5)
            var state = AppSnapshot(projects: [project], breakOffer: offer)
            try TimerEngine.setBreakDuration(&state, offer: offer, minutes: 12)
            XCTAssertEqual(state.breakOffer?.minutes, 12)
            XCTAssertNil(state.activeTimer)
            XCTAssertEqual(state.projects[0].shortBreakMinutes, kind == .shortBreak ? 12 : project.shortBreakMinutes)
            XCTAssertEqual(state.projects[0].longBreakMinutes, kind == .longBreak ? 12 : project.longBreakMinutes)
            try TimerEngine.startBreak(&state, now: now)
            XCTAssertEqual(state.activeTimer?.plannedSeconds, 720)
            let started = state
            XCTAssertThrowsError(try TimerEngine.setBreakDuration(&state, offer: offer, minutes: 15))
            XCTAssertEqual(state, started)
        }
    }

    func testStaleAndInvalidBreakChangesDoNotMutateState() throws {
        let project = Project(name: "Writing")
        let offer = BreakOffer(projectID: project.id, kind: .shortBreak, minutes: 5)
        let original = AppSnapshot(projects: [project], breakOffer: offer)
        for minutes in [0, 61] {
            var state = original
            XCTAssertThrowsError(try TimerEngine.setBreakDuration(&state, offer: offer, minutes: minutes))
            XCTAssertEqual(state, original)
        }
        var state = original
        let stale = BreakOffer(projectID: project.id, kind: .longBreak, minutes: 15)
        XCTAssertThrowsError(try TimerEngine.setBreakDuration(&state, offer: stale, minutes: 10))
        XCTAssertEqual(state, original)
    }

    func testPlanningLinksRoundTripAndRejectMalformedParameters() {
        let id = UUID()
        for scheme in AppURLScheme.allCases {
            let router = AppURLRouter(scheme: scheme)
            let route = AppRoute.planNextSession(projectID: id)
            XCTAssertEqual(router.parse(router.url(for: route)), route)
            for suffix in ["", "?project=no", "?project=\(id)&project=\(id)", "?project=\(id)&extra=1"] {
                XCTAssertNil(router.parse(URL(string: "\(scheme.rawValue)://plan/next\(suffix)")!))
            }
        }
    }

    func testLiveActivityOffersPlanningForBothBreakKindsAndThoughtsForFocus() throws {
        let project = Project(name: "Writing")
        for kind in [TimerKind.focus, .shortBreak, .longBreak] {
            let timer = ActiveTimer(projectID: project.id, kind: kind, startedAt: now,
                                    plannedSeconds: 300, shortBreakMinutes: 5, longBreakMinutes: 15, longBreakInterval: 4)
            let state = AppSnapshot(projects: [project], activeTimer: timer)
            let projection = try XCTUnwrap(LiveActivityProjection(state: state))
            XCTAssertEqual(projection.actionRoute, kind == .focus ? .captureThought(sessionID: timer.id) : .planNextSession(projectID: project.id))
            XCTAssertNil(projection.projectName)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(projection)) as? [String: Any])
            json.removeValue(forKey: "projectID")
            let old = try JSONDecoder().decode(LiveActivityProjection.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertEqual(old.actionRoute, kind == .focus ? .captureThought(sessionID: timer.id) : .timer)
        }
    }
}
