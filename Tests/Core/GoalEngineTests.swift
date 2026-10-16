import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class GoalEngineTests: XCTestCase {
    func testDailyEditsPreservePastAndRestDays() throws {
        let c = GoalEngine.calendar()
        let today = c.startOfDay(for: Date())
        let yesterday = c.date(byAdding: .day, value: -1, to: today)!
        var plan = GoalPlan(dailyRevisions: [], weeklyProjectRevisions: [])
        XCTAssertNil(GoalEngine.dailyTarget(on: yesterday, plan: plan, calendar: c))
        try GoalEngine.setDaily(&plan, minutes: Array(repeating: 60, count: 7), now: yesterday, calendar: c)
        try GoalEngine.setDaily(&plan, minutes: Array(repeating: 0, count: 7), now: today, calendar: c)
        XCTAssertEqual(GoalEngine.dailyTarget(on: yesterday, plan: plan, calendar: c), 60)
        XCTAssertEqual(GoalEngine.dailyTarget(on: today, plan: plan, calendar: c), 0)
        try GoalEngine.setDaily(&plan, minutes: Array(repeating: 90, count: 7), now: today, calendar: c)
        XCTAssertEqual(plan.dailyRevisions.count, 2)
        XCTAssertEqual(GoalEngine.dailyTarget(on: today, plan: plan, calendar: c), 90)
    }
    func testWeeklyChangesBeginNextMondayAndReplacePendingRevision() throws {
        let c = GoalEngine.calendar(), now = Date(), id = UUID()
        let monday = GoalEngine.week(containing: now, calendar: c).start
        let next = c.date(byAdding: .day, value: 7, to: monday)!
        var plan = GoalPlan()
        try GoalEngine.setWeekly(&plan, projectID: id, minutes: 120, now: now, calendar: c)
        try GoalEngine.setWeekly(&plan, projectID: id, minutes: 240, now: now, calendar: c)
        XCTAssertEqual(GoalEngine.weeklyTarget(projectID: id, weekStart: monday, plan: plan, calendar: c), 120)
        XCTAssertEqual(GoalEngine.weeklyTarget(projectID: id, weekStart: next, plan: plan, calendar: c), 240)
        try GoalEngine.setWeekly(&plan, projectID: id, minutes: nil, now: now, calendar: c)
        XCTAssertEqual(plan.weeklyProjectRevisions.count, 2)
        XCTAssertNil(GoalEngine.weeklyTarget(projectID: id, weekStart: next, plan: plan, calendar: c))
    }
    func testLegacyGoalHistoryBeginsOnImportDay() throws {
        let now = Date(), c = GoalEngine.calendar()
        let state = try BackupService.decode(MigrationFixtures.data("v1-history"), now: now, calendar: c)
        XCTAssertEqual(GoalEngine.dailyTarget(on: now, plan: state.goalPlan, calendar: c), 240)
        XCTAssertNil(GoalEngine.dailyTarget(on: c.date(byAdding: .day, value: -1, to: now)!, plan: state.goalPlan, calendar: c))
    }
}
