import Foundation

enum FocusPeriod: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
}
struct DailySummary: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var focusSeconds: TimeInterval = 0
    var completedCount = 0
    var interruptedCount = 0
    var targetMinutes: Int?
    var isFuture: Bool
}
struct ProjectDuration: Identifiable, Equatable {
    let id: UUID
    let name: String
    let seconds: TimeInterval
}
struct PeriodSummary: Equatable {
    let interval: DateInterval
    let totalSeconds: TimeInterval
    let elapsedDays: Int
    let completedCount: Int
    let interruptedCount: Int
    let days: [DailySummary]
    let projects: [ProjectDuration]
    let includesActive: Bool
    var averageSeconds: TimeInterval { elapsedDays > 0 ? totalSeconds / Double(elapsedDays) : 0 }
}
struct PeriodComparison: Equatable {
    let current: DateInterval
    let previous: DateInterval
    let currentSeconds: TimeInterval
    let previousSeconds: TimeInterval
    var delta: TimeInterval { currentSeconds - previousSeconds }
    var percentage: Double? { previousSeconds > 0 ? delta / previousSeconds * 100 : nil }
}
extension Statistics {
    static func interval(for period: FocusPeriod, containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let c = GoalEngine.calendar(calendar)
        return period == .week ? GoalEngine.week(containing: date, calendar: c) : c.dateInterval(of: .month, for: date)!
    }
    static func dailySummaries(_ state: AppSnapshot, interval: DateInterval, projectID: UUID? = nil,
                               now: Date, calendar: Calendar = .current) -> [DailySummary] {
        let c = GoalEngine.calendar(calendar)
        var result: [DailySummary] = []
        var indices: [Date: Int] = [:]
        var day = c.startOfDay(for: interval.start)
        while day < interval.end {
            indices[day] = result.count
            result.append(DailySummary(date: day, targetMinutes: GoalEngine.dailyTarget(on: day, plan: state.goalPlan, calendar: c), isFuture: day > now))
            day = c.date(byAdding: .day, value: 1, to: day)!
        }
        func distribute(start: Date, end: Date) {
            let from = max(start, interval.start), to = min(end, min(interval.end, now))
            guard to > from else { return }
            var date = c.startOfDay(for: from)
            while date < to {
                let next = c.date(byAdding: .day, value: 1, to: date)!
                if let i = indices[date] { result[i].focusSeconds += overlap(start: from, end: to, interval: DateInterval(start: date, end: next)) }
                date = next
            }
        }
        for session in state.sessions where projectID == nil || session.projectID == projectID {
            distribute(start: session.startedAt, end: session.endedAt)
            if session.startedAt >= interval.start, session.startedAt < interval.end, session.startedAt <= now,
               let i = indices[c.startOfDay(for: session.startedAt)] {
                if session.outcome == .completed { result[i].completedCount += 1 } else { result[i].interruptedCount += 1 }
            }
        }
        if let timer = state.activeTimer, timer.kind == .focus, projectID == nil || projectID == timer.projectID {
            distribute(start: timer.startedAt, end: timer.startedAt.addingTimeInterval(timer.elapsed(at: now)))
        }
        return result
    }
    static func periodSummary(_ state: AppSnapshot, interval: DateInterval, projectID: UUID? = nil,
                              now: Date, calendar: Calendar = .current) -> PeriodSummary {
        let days = dailySummaries(state, interval: interval, projectID: projectID, now: now, calendar: calendar)
        let bounded = DateInterval(start: interval.start, end: max(interval.start, min(interval.end, now)))
        var totals: [UUID: TimeInterval] = [:]
        for session in state.sessions where projectID == nil || session.projectID == projectID {
            totals[session.projectID, default: 0] += overlap(start: session.startedAt, end: session.endedAt, interval: bounded)
        }
        var includesActive = false
        if let timer = state.activeTimer, timer.kind == .focus, projectID == nil || timer.projectID == projectID {
            let amount = overlap(start: timer.startedAt, end: timer.startedAt.addingTimeInterval(timer.elapsed(at: now)), interval: bounded)
            totals[timer.projectID, default: 0] += amount
            includesActive = amount > 0
        }
        let projects = state.projects.compactMap { project -> ProjectDuration? in
            guard let seconds = totals[project.id], seconds > 0 else { return nil }
            return ProjectDuration(id: project.id, name: project.name, seconds: seconds)
        }.sorted { $0.seconds == $1.seconds ? $0.name < $1.name : $0.seconds > $1.seconds }
        return PeriodSummary(interval: interval, totalSeconds: days.reduce(0) { $0 + $1.focusSeconds },
                             elapsedDays: days.filter { !$0.isFuture }.count,
                             completedCount: days.reduce(0) { $0 + $1.completedCount },
                             interruptedCount: days.reduce(0) { $0 + $1.interruptedCount },
                             days: days, projects: projects, includesActive: includesActive)
    }
    static func periodComparison(_ state: AppSnapshot, period: FocusPeriod, interval: DateInterval,
                                 projectID: UUID? = nil, now: Date, calendar: Calendar = .current) -> PeriodComparison {
        let c = GoalEngine.calendar(calendar)
        let previousDate = c.date(byAdding: period == .week ? .day : .month, value: period == .week ? -7 : -1, to: interval.start)!
        let previous = self.interval(for: period, containing: previousDate, calendar: c)
        var currentRange = interval, previousRange = previous
        if now >= interval.start, now < interval.end {
            currentRange = DateInterval(start: interval.start, end: now)
            let offset = c.dateComponents([.day], from: interval.start, to: c.startOfDay(for: now)).day ?? 0
            let day = c.date(byAdding: .day, value: offset, to: previous.start)!
            var cutoff = previous.end
            if day < previous.end {
                cutoff = min(previous.end, c.date(bySettingHour: c.component(.hour, from: now), minute: c.component(.minute, from: now),
                    second: c.component(.second, from: now), of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first)!)
            }
            previousRange = DateInterval(start: previous.start, end: cutoff)
        }
        return PeriodComparison(current: currentRange, previous: previousRange,
            currentSeconds: total(state, projectID: projectID, interval: currentRange, now: now),
            previousSeconds: total(state, projectID: projectID, interval: previousRange, now: now))
    }
}
