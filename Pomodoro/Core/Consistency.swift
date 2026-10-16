import Foundation

struct ConsistencySummary: Equatable {
    let week: DateInterval
    let focusedDays: Int
    let targetDays: Int
    let isProvisional: Bool
}
extension Statistics {
    static func consistency(_ state: AppSnapshot, weekStart: Date, now: Date, calendar: Calendar = .current) -> ConsistencySummary {
        let week = GoalEngine.week(containing: weekStart, calendar: calendar)
        let days = dailySummaries(state, interval: week, now: now, calendar: calendar)
        var provisional = false
        if let timer = state.activeTimer, timer.kind == .focus, now >= week.start, now < week.end {
            let day = today(now, calendar: GoalEngine.calendar(calendar))
            var saved = state
            saved.activeTimer = nil
            provisional = total(state, interval: day, now: now) >= 600 && total(saved, interval: day, now: now) < 600
        }
        return ConsistencySummary(week: week, focusedDays: days.filter { $0.focusSeconds >= 600 }.count,
                                  targetDays: state.settings.consistencyTargetDays, isProvisional: provisional)
    }
}
