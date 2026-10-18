import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class PeriodStatisticsTests: XCTestCase {
    func testDailySummariesKeepProjectWorkAndTargetsSeparate() throws {
        var calendar = GoalEngine.calendar()
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12))!
        let work = Project(name: "Work"), reading = Project(name: "Reading")
        let start = calendar.startOfDay(for: now).addingTimeInterval(3600)
        let sessions = [
            FocusSession(id: UUID(), projectID: work.id, startedAt: start, endedAt: start.addingTimeInterval(1800), plannedSeconds: 1800, outcome: .interrupted),
            FocusSession(id: UUID(), projectID: reading.id, startedAt: start.addingTimeInterval(3600), endedAt: start.addingTimeInterval(4200), plannedSeconds: 600, outcome: .interrupted)
        ]
        var state = AppSnapshot(projects: [work, reading], sessions: sessions)
        try GoalEngine.setDaily(&state.goalPlan, projectID: work.id, minutes: Array(repeating: 240, count: 7), now: now, calendar: calendar)
        try GoalEngine.setDaily(&state.goalPlan, projectID: reading.id, minutes: Array(repeating: 60, count: 7), now: now, calendar: calendar)
        state.goalPlan.legacyDailyGoalTransitionDay = LocalDay(now, calendar: calendar)
        let interval = calendar.dateInterval(of: .day, for: now)!

        let workDay = Statistics.dailySummaries(state, interval: interval, projectID: work.id, now: now, calendar: calendar)[0]
        let readingDay = Statistics.dailySummaries(state, interval: interval, projectID: reading.id, now: now, calendar: calendar)[0]
        let allDay = Statistics.dailySummaries(state, interval: interval, now: now, calendar: calendar)[0]
        XCTAssertEqual(workDay.focusSeconds, 1800)
        XCTAssertEqual(workDay.targetMinutes, 240)
        XCTAssertEqual(readingDay.focusSeconds, 600)
        XCTAssertEqual(readingDay.targetMinutes, 60)
        XCTAssertEqual(allDay.focusSeconds, 2400)
        XCTAssertNil(allDay.targetMinutes)
    }

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
        var c = GoalEngine.calendar()
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = c.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 12))!
        let interval = Statistics.interval(for: .month, containing: now, calendar: c)
        let result = Statistics.periodComparison(AppSnapshot(), period: .month, interval: interval, now: now, calendar: c)
        XCTAssertEqual(result.previous.end, c.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        XCTAssertEqual(result.current.end, interval.end)
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

    func testLeapMonthZeroDaysProjectFilterAndActiveExclusion() throws {
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
        XCTAssertEqual(summary.totalSeconds, 600)
        XCTAssertEqual(summary.interruptedCount, 1)
        XCTAssertEqual(summary.projects.count, 1)
        let filtered = Statistics.periodSummary(state, interval: month, projectID: projects[0].id, now: now, calendar: calendar)
        XCTAssertEqual(filtered.totalSeconds, 0)
        XCTAssertEqual(filtered.completedCount + filtered.interruptedCount, 0)
        XCTAssertTrue(filtered.projects.isEmpty)
        XCTAssertTrue(filtered.days.allSatisfy { $0.targetMinutes == nil })
        state.activeTimer = nil
        let afterDiscard = Statistics.periodSummary(state, interval: month, projectID: projects[0].id, now: now, calendar: calendar)
        XCTAssertEqual(afterDiscard.totalSeconds, 0)
    }

    func testCurrentComparisonsIncludeWholeMatchingDayAndStayStableWithinDay() {
        var c = GoalEngine.calendar()
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ day: Int, _ hour: Int) -> Date {
            c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        let project = Project(name: "Writing")
        let current = FocusSession(id: UUID(), projectID: project.id, startedAt: date(14, 20),
            endedAt: date(14, 21), plannedSeconds: 3600, outcome: .completed)
        let previous = FocusSession(id: UUID(), projectID: project.id, startedAt: date(7, 22),
            endedAt: date(7, 23), plannedSeconds: 3600, outcome: .interrupted)
        let state = AppSnapshot(projects: [project], sessions: [current, previous])
        let week = Statistics.interval(for: .week, containing: date(14, 8), calendar: c)
        let morning = Statistics.periodComparison(state, period: .week, interval: week, now: date(14, 8), calendar: c)
        let evening = Statistics.periodComparison(state, period: .week, interval: week, now: date(14, 23), calendar: c)
        XCTAssertEqual(morning, evening)
        XCTAssertEqual(morning.current.end, date(15, 0))
        XCTAssertEqual(morning.previous.end, date(8, 0))
        XCTAssertEqual(morning.currentSeconds, 3600)
        XCTAssertEqual(morning.previousSeconds, 3600)
        let summary = Statistics.periodSummary(state, interval: week, now: date(14, 8), calendar: c)
        XCTAssertEqual(summary, Statistics.periodSummary(state, interval: week, now: date(14, 23), calendar: c))
        XCTAssertEqual(summary.totalSeconds, summary.projects.reduce(0) { $0 + $1.seconds })
        XCTAssertEqual(summary.totalSeconds, 3600)
        XCTAssertEqual(summary.completedCount, 1)
        let tomorrow = Statistics.periodSummary(state, interval: week, now: date(15, 0), calendar: c)
        XCTAssertEqual(tomorrow.elapsedDays, summary.elapsedDays + 1)
        let historical = Statistics.periodComparison(state, period: .week, interval: week, now: date(22, 8), calendar: c)
        XCTAssertEqual(historical.current, week)
        XCTAssertEqual(historical.previous, Statistics.interval(for: .week, containing: date(7, 8), calendar: c))
    }

    func testCurrentMonthMatchesDatesThroughEntirePreviousDay() {
        var c = GoalEngine.calendar()
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ month: Int, _ day: Int, _ hour: Int) -> Date {
            c.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        let project = Project(name: "Writing")
        let saved = FocusSession(id: UUID(), projectID: project.id, startedAt: date(9, 17, 22),
            endedAt: date(9, 17, 23), plannedSeconds: 3600, outcome: .completed)
        let excluded = FocusSession(id: UUID(), projectID: project.id, startedAt: date(9, 18, 0),
            endedAt: date(9, 18, 1), plannedSeconds: 3600, outcome: .completed)
        let state = AppSnapshot(projects: [project], sessions: [saved, excluded])
        let month = Statistics.interval(for: .month, containing: date(10, 17, 8), calendar: c)
        let morning = Statistics.periodComparison(state, period: .month, interval: month, now: date(10, 17, 8), calendar: c)
        XCTAssertEqual(morning, Statistics.periodComparison(state, period: .month, interval: month, now: date(10, 17, 23), calendar: c))
        XCTAssertEqual(morning.current.end, date(10, 18, 0))
        XCTAssertEqual(morning.previous.end, date(9, 18, 0))
        XCTAssertEqual(morning.previousSeconds, 3600)
    }

    func testMonthComparisonLeapClampAndFutureSummary() {
        var c = GoalEngine.calendar()
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = c.date(from: DateComponents(year: 2024, month: 3, day: 30, hour: 8))!
        let month = Statistics.interval(for: .month, containing: now, calendar: c)
        let result = Statistics.periodComparison(AppSnapshot(), period: .month, interval: month, now: now, calendar: c)
        XCTAssertEqual(c.component(.day, from: result.current.end), 31)
        XCTAssertEqual(result.previous.end, month.start)
        XCTAssertEqual(c.dateComponents([.day], from: result.previous.start, to: result.previous.end).day, 29)
        let future = Statistics.periodSummary(AppSnapshot(), interval: month, now: month.start.addingTimeInterval(-1), calendar: c)
        XCTAssertEqual(future.totalSeconds, 0)
        XCTAssertEqual(future.elapsedDays, 0)
        XCTAssertTrue(future.days.allSatisfy { $0.isFuture && $0.focusSeconds == 0 })
    }

    func testComparisonDayBoundariesAcrossBothStockholmDSTChanges() {
        var c = GoalEngine.calendar()
        c.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        for (month, day) in [(3, 29), (10, 25)] {
            let now = c.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            let week = Statistics.interval(for: .week, containing: now, calendar: c)
            let comparison = Statistics.periodComparison(AppSnapshot(), period: .week, interval: week, now: now, calendar: c)
            XCTAssertEqual(comparison.current.end, week.end)
            XCTAssertEqual(c.component(.hour, from: comparison.current.end), 0)
            XCTAssertEqual(c.component(.hour, from: comparison.previous.end), 0)
            XCTAssertEqual(c.dateComponents([.day], from: comparison.current.start, to: comparison.current.end).day, 7)
            XCTAssertEqual(c.dateComponents([.day], from: comparison.previous.start, to: comparison.previous.end).day, 7)
        }
    }

}
