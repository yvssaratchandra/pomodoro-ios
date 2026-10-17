import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class ConsistencyTests: XCTestCase {
    func testInterruptedSessionsCombineOnlyAfterSaving() throws {
        var c = GoalEngine.calendar()
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = c.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 1))!
        var state = AppSnapshot(projects: [Project(name: "Writing")])
        let id = state.projects[0].id
        try TimerEngine.startFocus(&state, projectID: id, minutes: 10, now: start)
        TimerEngine.finish(&state, now: start.addingTimeInterval(300), force: true)
        try TimerEngine.startFocus(&state, projectID: id, minutes: 10, now: start.addingTimeInterval(400))
        TimerEngine.finish(&state, now: start.addingTimeInterval(699), force: true)
        XCTAssertEqual(Statistics.consistency(state, weekStart: start, now: start.addingTimeInterval(700), calendar: c).focusedDays, 0)
        try TimerEngine.startFocus(&state, projectID: id, minutes: 10, now: start.addingTimeInterval(700))
        let current = Statistics.consistency(state, weekStart: start, now: start.addingTimeInterval(701), calendar: c)
        XCTAssertEqual(current.focusedDays, 0)
        TimerEngine.discardFocus(&state, timerID: state.activeTimer!.id)
        XCTAssertEqual(Statistics.consistency(state, weekStart: start, now: start.addingTimeInterval(702), calendar: c).focusedDays, 0)
        try TimerEngine.startFocus(&state, projectID: id, minutes: 10, now: start.addingTimeInterval(703))
        TimerEngine.finish(&state, now: start.addingTimeInterval(704), force: true)
        XCTAssertEqual(Statistics.consistency(state, weekStart: start, now: start.addingTimeInterval(704), calendar: c).focusedDays, 1)
        let session = state.sessions.removeLast()
        XCTAssertEqual(Statistics.consistency(state, weekStart: start, now: start.addingTimeInterval(704), calendar: c).focusedDays, 0)
        state.sessions.append(session)
        XCTAssertEqual(Statistics.consistency(state, weekStart: start, now: start.addingTimeInterval(704), calendar: c).focusedDays, 1)
    }
}
