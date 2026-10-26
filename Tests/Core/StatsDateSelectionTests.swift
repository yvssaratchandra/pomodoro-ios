import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class StatsDateSelectionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = GoalEngine.calendar()
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testEveryRangeCanReturnFromHistoryAndRejectsFutureNavigation() {
        // Include exact boundaries, year rollover, leap day, and month-end dates.
        for now in [date(2026, 10, 26, 0), date(2027, 1, 1, 0), date(2024, 2, 29), date(2026, 3, 31)] {
            for range in [StatsDateRange.day, .week, .month] {
                var selection = StatsDateSelection()
                selection.setRange(range)
                let current = selection.interval(now: now, calendar: calendar)!
                XCTAssertFalse(selection.canMoveForward(now: now, calendar: calendar))
                selection.move(-1, now: now, calendar: calendar)
                let previous = selection.interval(now: now, calendar: calendar)!
                XCTAssertEqual(previous.end, current.start)
                XCTAssertTrue(selection.canMoveForward(now: now, calendar: calendar))
                selection.move(-1, now: now, calendar: calendar)
                XCTAssertLessThan(selection.interval(now: now, calendar: calendar)!.start, previous.start)
                selection.move(1, now: now, calendar: calendar)
                XCTAssertEqual(selection.interval(now: now, calendar: calendar), previous)
                selection.move(1, now: now, calendar: calendar)
                XCTAssertEqual(selection.interval(now: now, calendar: calendar), current)
                XCTAssertTrue(selection.isCurrent(now: now, calendar: calendar))
                XCTAssertNil(selection.anchor)
                selection.move(1, now: now, calendar: calendar)
                XCTAssertEqual(selection.interval(now: now, calendar: calendar), current)
            }
        }
    }

    func testCalendarSelectionUsesEnclosingPeriodAndClampsFutureDates() {
        let now = date(2026, 10, 26)
        let chosen = date(2024, 2, 29)
        for range in [StatsDateRange.day, .week, .month] {
            var selection = StatsDateSelection()
            selection.setRange(range)
            selection.select(chosen, now: now, calendar: calendar)
            let expected = range.period.map { Statistics.interval(for: $0, containing: chosen, calendar: calendar) }
                ?? Statistics.today(chosen, calendar: calendar)
            XCTAssertEqual(selection.interval(now: now, calendar: calendar), expected)
            XCTAssertEqual(selection.anchor, expected.start)
            selection.select(date(2028, 1, 1), now: now, calendar: calendar)
            XCTAssertTrue(selection.isCurrent(now: now, calendar: calendar))
            XCTAssertNil(selection.anchor)
            selection.select(now, now: now, calendar: calendar)
            XCTAssertNil(selection.anchor)
        }
    }

    func testCurrentPeriodsFollowClockButHistoricalPeriodsStaySelected() {
        let now = date(2026, 12, 31)
        let later = date(2027, 2, 2)
        for range in [StatsDateRange.day, .week, .month] {
            var selection = StatsDateSelection()
            selection.setRange(range)
            let original = selection.interval(now: now, calendar: calendar)
            XCTAssertNotEqual(selection.interval(now: later, calendar: calendar), original)
            selection.move(-1, now: now, calendar: calendar)
            let historical = selection.interval(now: now, calendar: calendar)
            selection.reconcile(now: later, calendar: calendar)
            XCTAssertEqual(selection.interval(now: later, calendar: calendar), historical)
            selection.resetToCurrent()
            XCTAssertTrue(selection.isCurrent(now: later, calendar: calendar))
            XCTAssertNil(selection.anchor)
        }
    }

    func testClockMovingBackClampsSelectionToCurrentPeriod() {
        var selection = StatsDateSelection()
        let now = date(2026, 10, 26)
        selection.move(-1, now: now, calendar: calendar)
        let earlier = date(2026, 10, 23)
        XCTAssertEqual(selection.interval(now: earlier, calendar: calendar), Statistics.today(earlier, calendar: calendar))
        selection.reconcile(now: earlier, calendar: calendar)
        XCTAssertNil(selection.anchor)
    }

    func testRangeChangesResetDateAndAllDisablesDateNavigation() {
        let now = date(2026, 10, 26)
        var selection = StatsDateSelection()
        XCTAssertEqual(selection.range, .day)
        selection.move(-1, now: now, calendar: calendar)
        selection.setRange(.month)
        XCTAssertTrue(selection.isCurrent(now: now, calendar: calendar))
        selection.setRange(.all)
        selection.move(-1, now: now, calendar: calendar)
        selection.select(date(2024, 2, 29), now: now, calendar: calendar)
        XCTAssertNil(selection.interval(now: now, calendar: calendar))
        XCTAssertNil(selection.anchor)
        XCTAssertFalse(selection.canMoveForward(now: now, calendar: calendar))
    }

    func testDayNavigationUsesLocalDSTBoundaries() {
        for (month, day, hours) in [(3, 29, 23), (10, 25, 25)] {
            let now = date(2026, month, day + 1, 0)
            var selection = StatsDateSelection()
            selection.move(-1, now: now, calendar: calendar)
            let interval = selection.interval(now: now, calendar: calendar)!
            XCTAssertEqual(interval.start, date(2026, month, day, 0))
            XCTAssertEqual(interval.duration, Double(hours * 3600))
            selection.move(1, now: now, calendar: calendar)
            XCTAssertEqual(selection.interval(now: now, calendar: calendar)!.start, now)
        }
    }

    func testSelectedDayUsesHistoricalProjectGoalAndMidnightOverlap() throws {
        let now = date(2026, 10, 26)
        let yesterday = date(2026, 10, 25, 0)
        let today = calendar.startOfDay(for: now)
        let work = Project(name: "Work"), reading = Project(name: "Reading")
        var state = AppSnapshot(projects: [work, reading])
        try GoalEngine.setDaily(&state.goalPlan, projectID: work.id,
                                minutes: Array(repeating: 60, count: 7), now: yesterday, calendar: calendar)
        try GoalEngine.setDaily(&state.goalPlan, projectID: work.id,
                                minutes: Array(repeating: 240, count: 7), now: now, calendar: calendar)
        state.sessions = [
            FocusSession(id: UUID(), projectID: work.id, startedAt: today.addingTimeInterval(-600),
                         endedAt: today.addingTimeInterval(600), plannedSeconds: 1200, outcome: .completed),
            FocusSession(id: UUID(), projectID: reading.id, startedAt: yesterday.addingTimeInterval(3600),
                         endedAt: yesterday.addingTimeInterval(4800), plannedSeconds: 1200, outcome: .completed)
        ]
        try TimerEngine.startFocus(&state, projectID: work.id, minutes: 25, now: now.addingTimeInterval(-300))
        var selection = StatsDateSelection()
        selection.move(-1, now: now, calendar: calendar)
        let interval = selection.interval(now: now, calendar: calendar)!
        let summary = Statistics.dailySummaries(state, interval: interval, projectID: work.id, now: now, calendar: calendar)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary[0].targetMinutes, 60)
        XCTAssertEqual(summary[0].focusSeconds, 600)
        XCTAssertEqual(Statistics.total(state, projectID: work.id, interval: interval, now: now), 600)
        XCTAssertEqual(Statistics.total(state, interval: interval, now: now), 1800)
        XCTAssertFalse(Statistics.hasFocusInProgress(state, interval: interval, now: now))
        selection.resetToCurrent()
        XCTAssertEqual(GoalEngine.dailyTarget(projectID: work.id, on: selection.interval(now: now, calendar: calendar)!.start,
                                             plan: state.goalPlan, calendar: calendar), 240)
    }
}
