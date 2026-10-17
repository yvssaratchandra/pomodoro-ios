import Foundation

struct ConsistencySummary: Equatable {
    let week: DateInterval
    let focusedDays: Int
    let targetDays: Int
}
extension Statistics {
    static func consistency(_ state: AppSnapshot, weekStart: Date, now: Date, calendar: Calendar = .current) -> ConsistencySummary {
        let week = GoalEngine.week(containing: weekStart, calendar: calendar)
        let days = dailySummaries(state, interval: week, now: now, calendar: calendar)
        return ConsistencySummary(week: week, focusedDays: days.filter { $0.focusSeconds >= 600 }.count,
                                  targetDays: state.settings.consistencyTargetDays)
    }
}
