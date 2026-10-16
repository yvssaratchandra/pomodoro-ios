import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class PeriodStatisticsTests: XCTestCase {
    func testMidnightSplitCountsByStartAndAveragesIncludeZeroDays() throws {
        var c = GoalEngine.calendar(); c.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = c.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12))!
        let midnight = c.startOfDay(for: now)
        var state = AppSnapshot(projects: [Project(name: "Writing")])
        try TimerEngine.startFocus(&state, projectID: state.projects[0].id, minutes: 20, now: midnight.addingTimeInterval(-600))
        TimerEngine.finish(&state, now: midnight.addingTimeInterval(600))
        let interval = Statistics.interval(for: .week, containing: now, calendar: c)
        let summary = Statistics.periodSummary(state, interval: interval, now: now, calendar: c)
        XCTAssertEqual(summary.totalSeconds, 1200)
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(summary.elapsedDays, 5)
        XCTAssertEqual(summary.averageSeconds, 240)
        XCTAssertEqual(summary.days.filter { $0.focusSeconds == 600 }.count, 2)
        XCTAssertEqual(summary.projects.first?.seconds, 1200)
        let comparison = Statistics.periodComparison(state, period: .week, interval: interval, now: now, calendar: c)
        XCTAssertNil(comparison.percentage)
        XCTAssertEqual(comparison.delta, 1200)
    }
    func testLongMonthComparisonClampsAtPreviousMonthEnd() {
        let c = GoalEngine.calendar()
        let now = c.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 12))!
        let interval = Statistics.interval(for: .month, containing: now, calendar: c)
        let result = Statistics.periodComparison(AppSnapshot(), period: .month, interval: interval, now: now, calendar: c)
        XCTAssertEqual(result.previous.end, c.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        XCTAssertEqual(result.current.end, now)
    }
}
