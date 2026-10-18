import Foundation

struct LocalDay: Codable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int
    init(_ date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        year = c.year!; month = c.month!; day = c.day!
    }
    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day) }
    func date(calendar: Calendar) -> Date? {
        guard year > 0, (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              LocalDay(date, calendar: calendar) == self else { return nil }
        return date
    }
}
struct DailyGoalRevision: Codable, Equatable {
    var effectiveFrom: LocalDay
    var minutes: [Int]
}
struct ProjectWeeklyGoalRevision: Codable, Equatable {
    var projectID: UUID
    var effectiveFrom: LocalDay
    var minutes: Int?
}
struct ProjectDailyGoalRevision: Codable, Equatable {
    var projectID: UUID
    var effectiveFrom: LocalDay
    var minutes: [Int]
}
struct GoalPlan: Codable, Equatable {
    var dailyRevisions: [DailyGoalRevision] = []
    var weeklyProjectRevisions: [ProjectWeeklyGoalRevision] = []
    var dailyProjectRevisions: [ProjectDailyGoalRevision] = []
    var pendingLegacyDailySchedule: [Int]?
    var legacyDailyGoalTransitionDay: LocalDay?
}
enum GoalEngine {
    static func calendar(_ source: Calendar = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = source.timeZone; c.firstWeekday = 2; c.minimumDaysInFirstWeek = 4
        return c
    }
    static func week(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        self.calendar(calendar).dateInterval(of: .weekOfYear, for: date)!
    }
    static func dailyTarget(on date: Date, plan: GoalPlan, calendar: Calendar = .current) -> Int? {
        let c = self.calendar(calendar), day = LocalDay(date, calendar: c)
        guard let revision = plan.dailyRevisions.filter({ $0.effectiveFrom <= day }).max(by: { $0.effectiveFrom < $1.effectiveFrom }) else { return nil }
        return revision.minutes[(c.component(.weekday, from: date) + 5) % 7]
    }
    static func dailyTarget(projectID: UUID, on date: Date, plan: GoalPlan, calendar: Calendar = .current) -> Int? {
        let c = self.calendar(calendar), day = LocalDay(date, calendar: c)
        guard let revision = plan.dailyProjectRevisions
            .filter({ $0.projectID == projectID && $0.effectiveFrom <= day })
            .max(by: { $0.effectiveFrom < $1.effectiveFrom }) else { return nil }
        return revision.minutes[(c.component(.weekday, from: date) + 5) % 7]
    }
    static func dailySchedule(projectID: UUID, on date: Date, plan: GoalPlan, calendar: Calendar = .current) -> [Int]? {
        let day = LocalDay(date, calendar: self.calendar(calendar))
        return plan.dailyProjectRevisions
            .filter { $0.projectID == projectID && $0.effectiveFrom <= day }
            .max(by: { $0.effectiveFrom < $1.effectiveFrom })?.minutes
    }
    static func weeklyTarget(projectID: UUID, weekStart: Date, plan: GoalPlan, calendar: Calendar = .current) -> Int? {
        let day = LocalDay(week(containing: weekStart, calendar: calendar).start, calendar: self.calendar(calendar))
        return plan.weeklyProjectRevisions.filter { $0.projectID == projectID && $0.effectiveFrom <= day }
            .max(by: { $0.effectiveFrom < $1.effectiveFrom })?.minutes
    }
    static func setDaily(_ plan: inout GoalPlan, projectID: UUID, minutes: [Int], now: Date, calendar: Calendar = .current) throws {
        guard minutes.count == 7, minutes.allSatisfy({ (0...1440).contains($0) }) else { throw AppError.invalid("Choose seven daily targets from 0 to 1440 minutes.") }
        let day = LocalDay(now, calendar: self.calendar(calendar))
        plan.dailyProjectRevisions.removeAll { $0.projectID == projectID && $0.effectiveFrom == day }
        plan.dailyProjectRevisions.append(ProjectDailyGoalRevision(projectID: projectID, effectiveFrom: day, minutes: minutes))
    }
    static func weeklyEffectiveDate(projectID: UUID, plan: GoalPlan, now: Date, calendar: Calendar = .current) -> Date {
        week(containing: now, calendar: calendar).start
    }
    static func setWeekly(_ plan: inout GoalPlan, projectID: UUID, minutes: Int?, now: Date, calendar: Calendar = .current, effectiveWeek: Date? = nil) throws {
        guard minutes == nil || (1...10080).contains(minutes!) else { throw AppError.invalid("Weekly targets must be 1 to 10080 minutes.") }
        let monday = week(containing: effectiveWeek ?? now, calendar: calendar).start
        guard monday >= week(containing: now, calendar: calendar).start else {
            throw AppError.invalid("Choose this week or a future week.")
        }
        let day = LocalDay(monday, calendar: self.calendar(calendar))
        plan.weeklyProjectRevisions.removeAll { $0.projectID == projectID && $0.effectiveFrom == day }
        plan.weeklyProjectRevisions.append(ProjectWeeklyGoalRevision(projectID: projectID, effectiveFrom: day, minutes: minutes))
    }
    static func validate(_ plan: GoalPlan, projectIDs: Set<UUID>) throws {
        let c = calendar()
        guard Set(plan.dailyRevisions.map(\.effectiveFrom)).count == plan.dailyRevisions.count else { throw AppError.invalid("Duplicate daily goal revisions.") }
        for r in plan.dailyRevisions {
            guard r.effectiveFrom.date(calendar: c) != nil, r.minutes.count == 7, r.minutes.allSatisfy({ (0...1440).contains($0) }) else { throw AppError.invalid("Invalid daily goal schedule.") }
        }
        if let transition = plan.legacyDailyGoalTransitionDay, transition.date(calendar: c) == nil {
            throw AppError.invalid("Invalid previous daily goal date.")
        }
        if let legacy = plan.pendingLegacyDailySchedule {
            guard plan.legacyDailyGoalTransitionDay != nil,
                  legacy.count == 7, legacy.allSatisfy({ (0...1440).contains($0) }) else {
                throw AppError.invalid("Invalid previous daily goal schedule.")
            }
        }
        var dailyKeys = Set<String>()
        for revision in plan.dailyProjectRevisions {
            guard projectIDs.contains(revision.projectID), revision.effectiveFrom.date(calendar: c) != nil,
                  revision.minutes.count == 7, revision.minutes.allSatisfy({ (0...1440).contains($0) }),
                  dailyKeys.insert("\(revision.projectID)-\(revision.effectiveFrom)").inserted else {
                throw AppError.invalid("Invalid project daily goal.")
            }
        }
        var keys = Set<String>()
        for r in plan.weeklyProjectRevisions {
            guard projectIDs.contains(r.projectID), let date = r.effectiveFrom.date(calendar: c), c.component(.weekday, from: date) == 2,
                  r.minutes == nil || (1...10080).contains(r.minutes!),
                  keys.insert("\(r.projectID)-\(r.effectiveFrom)").inserted else { throw AppError.invalid("Invalid project weekly goal.") }
        }
    }
}
