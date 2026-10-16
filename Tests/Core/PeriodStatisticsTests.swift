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
    func testStockholmDSTDaysUseCalendarBoundariesAndElapsedSeconds() {
        var calendar = GoalEngine.calendar()
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        for (month, day, hours) in [(3, 29, 23), (10, 25, 25)] {
            let start = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
            let next = calendar.date(byAdding: .day, value: 1, to: start)!
            XCTAssertEqual(next.timeIntervalSince(start), Double(hours * 3600))
            let project = Project(name: "Writing")
            let sessionStart = calendar.date(bySettingHour: 1, minute: 30, second: 0, of: start)!
            let session = FocusSession(id: UUID(), projectID: project.id, startedAt: sessionStart,
                endedAt: sessionStart.addingTimeInterval(3600), plannedSeconds: 3600, outcome: .completed)
            let state = AppSnapshot(projects: [project], sessions: [session])
            let summary = Statistics.periodSummary(state, interval: DateInterval(start: start, end: next), now: next, calendar: calendar)
            XCTAssertEqual(summary.days.count, 1)
            XCTAssertEqual(summary.totalSeconds, 3600)
            XCTAssertEqual(summary.averageSeconds, 3600)
            XCTAssertEqual(summary.completedCount, 1)
            let week = GoalEngine.week(containing: start, calendar: calendar)
            XCTAssertEqual(calendar.component(.weekday, from: week.start), 2)
            XCTAssertEqual(calendar.dateComponents([.day], from: week.start, to: week.end).day, 7)
        }
    }

    func testLeapMonthZeroDaysProjectFilterAndCappedActiveContribution() throws {
        var calendar = GoalEngine.calendar()
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let leapDay = calendar.date(from: DateComponents(year: 2024, month: 2, day: 29, hour: 12))!
        let month = Statistics.interval(for: .month, containing: leapDay, calendar: calendar)
        let projects = [Project(name: "Writing"), Project(name: "Study", status: .completed)]
        let saved = FocusSession(id: UUID(), projectID: projects[1].id, startedAt: leapDay.addingTimeInterval(-600),
                                endedAt: leapDay, plannedSeconds: 600, outcome: .interrupted)
        var state = AppSnapshot(projects: projects, sessions: [saved])
        try TimerEngine.startFocus(&state, projectID: projects[0].id, minutes: 10, now: leapDay)
        let now = leapDay.addingTimeInterval(900)
        let summary = Statistics.periodSummary(state, interval: month, now: now, calendar: calendar)
        XCTAssertEqual(summary.days.count, 29)
        XCTAssertEqual(summary.elapsedDays, 29)
        XCTAssertEqual(summary.totalSeconds, 1200)
        XCTAssertEqual(summary.interruptedCount, 1)
        XCTAssertTrue(summary.includesActive)
        XCTAssertEqual(summary.projects.count, 2)
        let filtered = Statistics.periodSummary(state, interval: month, projectID: projects[0].id, now: now, calendar: calendar)
        XCTAssertEqual(filtered.totalSeconds, 600)
        XCTAssertEqual(filtered.completedCount + filtered.interruptedCount, 0)
        XCTAssertEqual(filtered.projects.map(\.id), [projects[0].id])
        XCTAssertTrue(filtered.days.allSatisfy { $0.targetMinutes == nil })
        state.activeTimer = nil
        let afterDiscard = Statistics.periodSummary(state, interval: month, projectID: projects[0].id, now: now, calendar: calendar)
        XCTAssertEqual(afterDiscard.totalSeconds, 0)
        XCTAssertFalse(afterDiscard.includesActive)
    }

}
