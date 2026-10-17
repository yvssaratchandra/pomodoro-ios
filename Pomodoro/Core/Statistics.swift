import Foundation

enum Statistics {
    static func overlap(start: Date, end: Date, interval: DateInterval) -> TimeInterval {
        max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start)))
    }

    static func total(_ state: AppSnapshot, projectID: UUID? = nil,
                      interval: DateInterval? = nil, now: Date) -> TimeInterval {
        // Retain now for source compatibility; saved durations do not depend on the clock.
        state.sessions.filter { projectID == nil || $0.projectID == projectID }.reduce(0.0) { sum, session in
            sum + (interval.map { range in overlap(start: session.startedAt, end: session.endedAt, interval: range) } ?? session.duration)
        }
    }

    static func hasFocusInProgress(_ state: AppSnapshot, projectID: UUID? = nil,
                                   interval: DateInterval? = nil, now: Date) -> Bool {
        guard let timer = state.activeTimer, timer.kind == .focus,
              projectID == nil || timer.projectID == projectID,
              timer.startedAt <= now, now < timer.deadline else { return false }
        guard let interval else { return true }
        guard interval.end > interval.start else { return false }
        if now == timer.startedAt {
            return timer.startedAt >= interval.start && timer.startedAt < interval.end
        }
        return overlap(start: timer.startedAt, end: now, interval: interval) > 0
    }

    static func today(_ date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)!
    }

    static func dailyAverage(_ state: AppSnapshot, projectID: UUID, now: Date,
                             calendar: Calendar = .current) -> TimeInterval {
        let end = today(now, calendar: calendar).end
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        return total(state, projectID: projectID, interval: DateInterval(start: start, end: end), now: now) / 7
    }

    static func sessionsToday(_ state: AppSnapshot, now: Date, calendar: Calendar = .current) -> [FocusSession] {
        let day = today(now, calendar: calendar)
        return state.sessions.filter {
            overlap(start: $0.startedAt, end: $0.endedAt, interval: day) > 0 ||
            ($0.duration == 0 && $0.startedAt >= day.start && $0.startedAt < day.end)
        }.sorted { $0.startedAt > $1.startedAt }
    }
}
