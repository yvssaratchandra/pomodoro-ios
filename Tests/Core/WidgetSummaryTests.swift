import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class WidgetSummaryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return value
    }

    func testFreshnessUsesLocalDayTimezoneAndDST() throws {
        for (month, day, hours) in [(3, 29, 23), (10, 25, 25)] {
            let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day)))
            let interval = try XCTUnwrap(calendar.dateInterval(of: .day, for: start))
            let summary = WidgetSnapshot.SavedFocus(dayStart: interval.start, dayEnd: interval.end,
                timeZoneIdentifier: calendar.timeZone.identifier, seconds: 125.9)
            XCTAssertEqual(interval.duration, Double(hours * 3600))
            XCTAssertTrue(summary.isFresh(at: start, timeZone: calendar.timeZone))
            XCTAssertTrue(summary.isFresh(at: interval.end.addingTimeInterval(-1), timeZone: calendar.timeZone))
            XCTAssertFalse(summary.isFresh(at: interval.end, timeZone: calendar.timeZone))
            XCTAssertFalse(summary.isFresh(at: start.addingTimeInterval(-1), timeZone: calendar.timeZone))
            XCTAssertFalse(summary.isFresh(at: start, timeZone: TimeZone(secondsFromGMT: 0)!))
            XCTAssertEqual(summary.wholeMinutes, 2)
        }
    }

    func testMalformedSummariesNeverBecomeFresh() {
        let start = Date(timeIntervalSince1970: 0)
        for seconds in [-1.0, .infinity, .nan] {
            let summary = WidgetSnapshot.SavedFocus(dayStart: start, dayEnd: start.addingTimeInterval(86400),
                timeZoneIdentifier: "GMT", seconds: seconds)
            XCTAssertFalse(summary.isValid)
            XCTAssertFalse(summary.isFresh(at: start))
            XCTAssertEqual(summary.wholeMinutes, 0)
        }
        XCTAssertFalse(WidgetSnapshot.SavedFocus(dayStart: start, dayEnd: start,
            timeZoneIdentifier: "GMT", seconds: 0).isValid)
        XCTAssertFalse(WidgetSnapshot.SavedFocus(dayStart: start, dayEnd: start.addingTimeInterval(86400),
            timeZoneIdentifier: "invalid-zone", seconds: 0).isValid)
    }

    func testTimelineRefreshesAtMidnightOrInFifteenMinutes() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17)))
        XCTAssertEqual(WidgetSnapshot.nextRefresh(after: start, calendar: calendar), start.addingTimeInterval(900))
        let end = try XCTUnwrap(calendar.dateInterval(of: .day, for: start)).end
        XCTAssertEqual(WidgetSnapshot.nextRefresh(after: end.addingTimeInterval(-60), calendar: calendar), end)
    }

    func testThoughtRoutingPinsOnlyFocusAndExpiredTimersNeverOfferStart() {
        let project = Project(name: "Writing")
        let now = Date()
        XCTAssertEqual(WidgetSnapshot(state: AppSnapshot(projects: [project]), now: now).thoughtRoute,
                       .captureThought(sessionID: nil))
        for kind in [TimerKind.focus, .shortBreak, .longBreak] {
            let timer = ActiveTimer(projectID: project.id, kind: kind, startedAt: now.addingTimeInterval(-3600),
                plannedSeconds: 300, shortBreakMinutes: 0, longBreakMinutes: 0, longBreakInterval: 4)
            let snapshot = WidgetSnapshot(state: AppSnapshot(projects: [project], activeTimer: timer), now: now)
            XCTAssertEqual(snapshot.route(for: project.id), .timer)
            XCTAssertEqual(snapshot.thoughtRoute, .captureThought(sessionID: kind == .focus ? timer.id : nil))
        }
    }

    func testSavedDailySummaryExcludesActiveAndSplitsCrossMidnightSession() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17)))
        let project = Project(name: "Writing")
        let saved = FocusSession(id: UUID(), projectID: project.id, startedAt: start.addingTimeInterval(-120),
            endedAt: start.addingTimeInterval(180), plannedSeconds: 300, outcome: .interrupted)
        let timer = ActiveTimer(projectID: project.id, kind: .focus, startedAt: start.addingTimeInterval(200),
            plannedSeconds: 600, shortBreakMinutes: 0, longBreakMinutes: 0, longBreakInterval: 4)
        let state = AppSnapshot(projects: [project], sessions: [saved], activeTimer: timer)
        let day = Statistics.today(start, calendar: calendar)
        let seconds = Statistics.total(state, interval: day, now: start.addingTimeInterval(400))
        let summary = WidgetSnapshot.SavedFocus(dayStart: day.start, dayEnd: day.end,
            timeZoneIdentifier: calendar.timeZone.identifier, seconds: seconds)
        let snapshot = WidgetSnapshot(state: state, now: start, savedFocus: summary)
        XCTAssertEqual(snapshot.savedFocus?.seconds, 180)
        XCTAssertEqual(snapshot.savedFocus?.wholeMinutes, 3)
    }
}
