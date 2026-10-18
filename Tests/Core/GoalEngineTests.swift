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
        let projectID = UUID()
        var plan = GoalPlan()
        XCTAssertNil(GoalEngine.dailyTarget(projectID: projectID, on: yesterday, plan: plan, calendar: c))
        try GoalEngine.setDaily(&plan, projectID: projectID, minutes: Array(repeating: 60, count: 7), now: yesterday, calendar: c)
        try GoalEngine.setDaily(&plan, projectID: projectID, minutes: Array(repeating: 0, count: 7), now: today, calendar: c)
        XCTAssertEqual(GoalEngine.dailyTarget(projectID: projectID, on: yesterday, plan: plan, calendar: c), 60)
        XCTAssertEqual(GoalEngine.dailyTarget(projectID: projectID, on: today, plan: plan, calendar: c), 0)
        try GoalEngine.setDaily(&plan, projectID: projectID, minutes: Array(repeating: 90, count: 7), now: today, calendar: c)
        XCTAssertEqual(plan.dailyProjectRevisions.count, 2)
        XCTAssertEqual(GoalEngine.dailyTarget(projectID: projectID, on: today, plan: plan, calendar: c), 90)
    }
    func testDailyGoalsAreIsolatedBetweenProjects() throws {
        let c = GoalEngine.calendar(), now = Date()
        let work = UUID(), reading = UUID()
        var plan = GoalPlan()
        try GoalEngine.setDaily(&plan, projectID: work, minutes: Array(repeating: 240, count: 7), now: now, calendar: c)
        try GoalEngine.setDaily(&plan, projectID: reading, minutes: Array(repeating: 60, count: 7), now: now, calendar: c)
        XCTAssertEqual(GoalEngine.dailyTarget(projectID: work, on: now, plan: plan, calendar: c), 240)
        XCTAssertEqual(GoalEngine.dailyTarget(projectID: reading, on: now, plan: plan, calendar: c), 60)
        XCTAssertNil(GoalEngine.dailyTarget(projectID: UUID(), on: now, plan: plan, calendar: c))
    }
    func testWeeklyChangesApplyThisWeekAndPreserveScheduledAndPastTargets() throws {
        let c = GoalEngine.calendar(), now = Date(), id = UUID()
        let monday = GoalEngine.week(containing: now, calendar: c).start
        let next = c.date(byAdding: .day, value: 7, to: monday)!
        var plan = GoalPlan()
        let previous = c.date(byAdding: .day, value: -7, to: monday)!
        try GoalEngine.setWeekly(&plan, projectID: id, minutes: 60, now: previous, calendar: c)
        try GoalEngine.setWeekly(&plan, projectID: id, minutes: 120, now: now, calendar: c)
        try GoalEngine.setWeekly(&plan, projectID: id, minutes: 300, now: now, calendar: c, effectiveWeek: next)
        try GoalEngine.setWeekly(&plan, projectID: id, minutes: 240, now: now, calendar: c)
        XCTAssertEqual(GoalEngine.weeklyTarget(projectID: id, weekStart: previous, plan: plan, calendar: c), 60)
        XCTAssertEqual(GoalEngine.weeklyTarget(projectID: id, weekStart: monday, plan: plan, calendar: c), 240)
        XCTAssertEqual(GoalEngine.weeklyTarget(projectID: id, weekStart: next, plan: plan, calendar: c), 300)
        try GoalEngine.setWeekly(&plan, projectID: id, minutes: nil, now: now, calendar: c)
        XCTAssertEqual(plan.weeklyProjectRevisions.count, 3)
        XCTAssertNil(GoalEngine.weeklyTarget(projectID: id, weekStart: monday, plan: plan, calendar: c))
        XCTAssertEqual(GoalEngine.weeklyTarget(projectID: id, weekStart: next, plan: plan, calendar: c), 300)
        XCTAssertThrowsError(try GoalEngine.setWeekly(&plan, projectID: id, minutes: 90, now: now, calendar: c, effectiveWeek: previous))
    }
    func testLegacyGoalHistoryBeginsOnImportDay() throws {
        let now = Date(), c = GoalEngine.calendar()
        let state = try BackupService.decode(MigrationFixtures.data("v1-history"), now: now, calendar: c)
        XCTAssertEqual(GoalEngine.dailyTarget(on: now, plan: state.goalPlan, calendar: c), 240)
        XCTAssertNil(GoalEngine.dailyTarget(on: c.date(byAdding: .day, value: -1, to: now)!, plan: state.goalPlan, calendar: c))
    }
}
