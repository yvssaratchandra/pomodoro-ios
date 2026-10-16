import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class ConsistencyTests: XCTestCase {
    func testInterruptedSessionsCombineAndActiveQualificationIsProvisional() throws {
        let c = GoalEngine.calendar()
        let start = c.startOfDay(for: Date()).addingTimeInterval(3600)
        var state = AppSnapshot(projects: [Project(name: "Writing")])
        let id = state.projects[0].id
        try TimerEngine.startFocus(&state, projectID: id, minutes: 10, now: start)
        TimerEngine.finish(&state, now: start.addingTimeInterval(300), force: true)
        try TimerEngine.startFocus(&state, projectID: id, minutes: 10, now: start.addingTimeInterval(400))
        TimerEngine.finish(&state, now: start.addingTimeInterval(699), force: true)
        XCTAssertEqual(Statistics.consistency(state, weekStart: start, now: start.addingTimeInterval(700)).focusedDays, 0)
        try TimerEngine.startFocus(&state, projectID: id, minutes: 10, now: start.addingTimeInterval(700))
        let current = Statistics.consistency(state, weekStart: start, now: start.addingTimeInterval(701))
        XCTAssertEqual(current.focusedDays, 1)
        XCTAssertTrue(current.isProvisional)
        TimerEngine.discardFocus(&state, timerID: state.activeTimer!.id)
        XCTAssertEqual(Statistics.consistency(state, weekStart: start, now: start.addingTimeInterval(702)).focusedDays, 0)
    }
}
