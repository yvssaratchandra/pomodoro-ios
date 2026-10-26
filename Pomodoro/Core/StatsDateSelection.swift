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
