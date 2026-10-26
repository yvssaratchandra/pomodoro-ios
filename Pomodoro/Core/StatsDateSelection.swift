import Foundation

enum StatsDateRange: String, CaseIterable, Identifiable {
    case day = "Day", week = "Week", month = "Month", all = "All"
    var id: String { rawValue }
    var period: FocusPeriod? {
        switch self {
        case .week: .week
        case .month: .month
        default: nil
        }
    }
}

struct StatsDateSelection {
    private(set) var range: StatsDateRange = .day
    // A nil anchor follows the current period as the clock advances.
    private(set) var anchor: Date?

    func interval(now: Date, calendar: Calendar = .current) -> DateInterval? {
        let current = interval(containing: now, calendar: calendar)
        guard let anchor, let selected = interval(containing: anchor, calendar: calendar),
              let current else { return current }
        return selected.start < current.start ? selected : current
    }

    func isCurrent(now: Date, calendar: Calendar = .current) -> Bool {
        guard let selected = interval(now: now, calendar: calendar),
              let current = interval(containing: now, calendar: calendar) else { return true }
        return selected.start == current.start
    }

    func canMoveForward(now: Date, calendar: Calendar = .current) -> Bool {
        range != .all && !isCurrent(now: now, calendar: calendar)
    }

    mutating func setRange(_ range: StatsDateRange) {
        self.range = range
        resetToCurrent()
    }

    mutating func select(_ date: Date, now: Date, calendar: Calendar = .current) {
        guard let selected = interval(containing: date, calendar: calendar),
              let current = interval(containing: now, calendar: calendar) else { return }
        anchor = selected.start < current.start ? selected.start : nil
    }

    mutating func move(_ offset: Int, now: Date, calendar: Calendar = .current) {
        guard offset == -1 || offset == 1, range != .all,
              offset < 0 || canMoveForward(now: now, calendar: calendar),
              let start = interval(now: now, calendar: calendar)?.start else { return }
        let c = GoalEngine.calendar(calendar)
        let component: Calendar.Component = range == .month ? .month : .day
        let amount = range == .week ? offset * 7 : offset
        guard let date = c.date(byAdding: component, value: amount, to: start) else { return }
        select(date, now: now, calendar: c)
    }

    mutating func resetToCurrent() { anchor = nil }

    mutating func reconcile(now: Date, calendar: Calendar = .current) {
        if let anchor { select(anchor, now: now, calendar: calendar) }
    }

    private func interval(containing date: Date, calendar: Calendar) -> DateInterval? {
        let c = GoalEngine.calendar(calendar)
        switch range {
        case .day: return Statistics.today(date, calendar: c)
        case .week, .month: return Statistics.interval(for: range.period!, containing: date, calendar: c)
        case .all: return nil
        }
    }
}

enum StatsPeriodOptions {
    static func months(in year: Int, now: Date, calendar: Calendar = .current) -> [Date] {
        let c = GoalEngine.calendar(calendar)
        guard year > 0, year <= c.component(.year, from: now) else { return [] }
        let current = c.dateInterval(of: .month, for: now)!.start
        return (1...12).compactMap { month in
            c.date(from: DateComponents(year: year, month: month, day: 1))
        }.filter { $0 <= current }
    }

    static func weeks(in year: Int, now: Date, calendar: Calendar = .current) -> [DateInterval] {
        let c = GoalEngine.calendar(calendar)
        guard year > 0, year <= c.component(.yearForWeekOfYear, from: now) else { return [] }
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = 1
        components.weekday = c.firstWeekday
        guard var start = c.date(from: components) else { return [] }
        let current = GoalEngine.week(containing: now, calendar: c).start
        var result: [DateInterval] = []
        while c.component(.yearForWeekOfYear, from: start) == year, start <= current {
            let week = GoalEngine.week(containing: start, calendar: c)
            result.append(week)
            start = week.end
        }
        return result
    }

    static func years(for range: StatsDateRange, selected: Date, earliest: Date?, now: Date,
                      calendar: Calendar = .current) -> ClosedRange<Int> {
        let c = GoalEngine.calendar(calendar)
        let component: Calendar.Component = range == .week ? .yearForWeekOfYear : .year
        let currentYear = c.component(component, from: now)
        let firstYear = [selected, earliest ?? now, now].map { c.component(component, from: $0) }.min()!
        return max(1, firstYear)...currentYear
    }
}
