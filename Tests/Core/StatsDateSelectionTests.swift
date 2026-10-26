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

    func testMonthOptionsExcludeFutureMonthsAndIncludeEarlierYearsInFull() {
        let now = date(2026, 10, 26)
        let current = StatsPeriodOptions.months(in: 2026, now: now, calendar: calendar)
        XCTAssertEqual(current.count, 10)
        XCTAssertEqual(current.first, date(2026, 1, 1, 0))
        XCTAssertEqual(current.last, date(2026, 10, 1, 0))
        XCTAssertEqual(StatsPeriodOptions.months(in: 2025, now: now, calendar: calendar).count, 12)
        XCTAssertTrue(StatsPeriodOptions.months(in: 2027, now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(StatsPeriodOptions.months(in: 0, now: now, calendar: calendar).isEmpty)
        XCTAssertEqual(StatsPeriodOptions.months(in: 2026, now: date(2026, 1, 1, 0), calendar: calendar).count, 1)
    }

    func testWeekOptionsUseWeekYearsAndHandleWeek53AndDST() {
        let endOf2020 = date(2020, 12, 31)
        let weeks = StatsPeriodOptions.weeks(in: 2020, now: endOf2020, calendar: calendar)
        XCTAssertEqual(weeks.count, 53)
        XCTAssertEqual(weeks.first?.start, date(2019, 12, 30, 0))
        XCTAssertEqual(weeks.last?.end, date(2021, 1, 4, 0))
        for week in weeks {
            XCTAssertEqual(calendar.component(.weekday, from: week.start), 2)
            XCTAssertEqual(calendar.dateComponents([.day], from: week.start, to: week.end).day, 7)
            XCTAssertLessThanOrEqual(week.start, endOf2020)
        }
        let december = date(2025, 12, 30)
        let nextWeekYear = StatsPeriodOptions.weeks(in: 2026, now: december, calendar: calendar)
        XCTAssertEqual(nextWeekYear.count, 1)
        XCTAssertEqual(nextWeekYear.first?.start, date(2025, 12, 29, 0))
        XCTAssertTrue(StatsPeriodOptions.weeks(in: 2027, now: december, calendar: calendar).isEmpty)
        XCTAssertTrue(StatsPeriodOptions.weeks(in: 0, now: december, calendar: calendar).isEmpty)
    }

    func testPickerYearsIncludeHistoryAndSelectionUsingTheCorrectYearKind() {
        let now = date(2025, 12, 30)
        XCTAssertEqual(StatsPeriodOptions.years(for: .week, selected: now, earliest: date(2020, 12, 31),
                                               now: now, calendar: calendar), 2020...2026)
        XCTAssertEqual(StatsPeriodOptions.years(for: .month, selected: now, earliest: date(2020, 12, 31),
                                               now: now, calendar: calendar), 2020...2025)
        XCTAssertEqual(StatsPeriodOptions.years(for: .month, selected: date(2019, 1, 1), earliest: date(2020, 1, 1),
                                               now: now, calendar: calendar), 2019...2025)
        XCTAssertEqual(StatsPeriodOptions.years(for: .month, selected: now, earliest: nil,
                                               now: now, calendar: calendar), 2025...2025)
    }
}
