import Foundation

struct WidgetSnapshot: Codable, Equatable {
    static let currentFormatVersion = 3

    struct SavedFocus: Codable, Equatable {
        let dayStart: Date
        let dayEnd: Date
        let timeZoneIdentifier: String
        let seconds: TimeInterval

        var isValid: Bool {
            dayStart.timeIntervalSince1970.isFinite && dayEnd.timeIntervalSince1970.isFinite &&
            dayEnd > dayStart && TimeZone(identifier: timeZoneIdentifier) != nil &&
            seconds.isFinite && seconds >= 0
        }

        func isFresh(at date: Date, timeZone: TimeZone = .current) -> Bool {
            guard isValid, timeZone.identifier == timeZoneIdentifier,
                  date >= dayStart, date < dayEnd else { return false }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            guard let day = calendar.dateInterval(of: .day, for: date) else { return false }
            return day.start == dayStart && day.end == dayEnd
        }

        var wholeMinutes: Int {
            guard seconds.isFinite, seconds >= 0 else { return 0 }
            return Int(min(floor(seconds / 60), Double(Int.max / 2)))
        }
    }

    struct Project: Codable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let preferredFocusMinutes: Int
    }

    struct Timer: Codable, Equatable, Identifiable {
        let id: UUID
        let projectID: UUID?
        let kind: TimerKind
        let projectName: String
        let startedAt: Date
        let deadline: Date
    }

    struct ProjectDaySummary: Codable, Equatable {
        let projectID: UUID
        let savedFocus: SavedFocus
        let targetMinutes: Int?
    }

    let formatVersion: Int
    let generatedAt: Date
    let projects: [Project]
    let activeTimer: Timer?
    let savedFocus: SavedFocus?
    let projectDaySummaries: [ProjectDaySummary]?

    init(state: AppSnapshot, now: Date, savedFocus: SavedFocus? = nil,
         projectDaySummaries: [ProjectDaySummary]? = nil) {
        formatVersion = Self.currentFormatVersion
        generatedAt = now
        self.savedFocus = savedFocus
        self.projectDaySummaries = projectDaySummaries
        projects = state.projects.filter { $0.status == .ongoing }.map {
            Project(id: $0.id, name: $0.name, preferredFocusMinutes: $0.preferredFocusMinutes)
        }
        activeTimer = state.activeTimer.map { timer in
            Timer(id: timer.id, projectID: timer.projectID, kind: timer.kind,
                  projectName: state.projects.first { $0.id == timer.projectID }?.name ?? "Project",
                  startedAt: timer.startedAt, deadline: timer.deadline)
        }
    }

    func projectSummary(for projectID: UUID, at date: Date, timeZone: TimeZone = .current) -> ProjectDaySummary? {
        guard let summary = projectDaySummaries?.first(where: { $0.projectID == projectID }),
              summary.savedFocus.isFresh(at: date, timeZone: timeZone) else { return nil }
        return summary
    }

    func hasSameDisplayContent(as other: WidgetSnapshot) -> Bool {
        formatVersion == other.formatVersion && projects == other.projects && activeTimer == other.activeTimer &&
        savedFocus == other.savedFocus && projectDaySummaries == other.projectDaySummaries
    }

    var thoughtRoute: AppRoute {
        .captureThought(sessionID: activeTimer.flatMap { $0.kind == .focus ? $0.id : nil })
    }

    static func nextRefresh(after date: Date, calendar: Calendar = .current) -> Date {
        let regular = date.addingTimeInterval(900)
        return calendar.dateInterval(of: .day, for: date).map { min(regular, $0.end) } ?? regular
    }

    func route(for projectID: UUID?) -> AppRoute {
        // Keep expired timers until the app reconciles them. A stale widget
        // must open the timer instead of offering a replacement start.
        if activeTimer != nil { return .timer }
        if projects.isEmpty { return .newProject }
        guard let projectID, projects.contains(where: { $0.id == projectID }) else { return .timer }
        return .startFocus(projectID: projectID)
    }
}

enum AppRoute: Equatable {
    case startFocus(projectID: UUID)
    case timer
    case newProject
    case captureThought(sessionID: UUID?)
    case planNextSession(projectID: UUID)
}

enum AppURLScheme: String, CaseIterable {
    case container = "pomodoro"
    case native = "pomodoro-native"
}

struct AppURLRouter {
    let scheme: AppURLScheme

    func parse(_ url: URL) -> AppRoute? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme.rawValue,
              components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil else { return nil }

        switch components.host?.lowercased() {
        case "focus":
            guard components.path.isEmpty,
                  let items = components.queryItems, items.count == 2,
                  Set(items.map(\.name)) == Set(["project", "action"]),
                  items.first(where: { $0.name == "action" })?.value == "start",
                  let value = items.first(where: { $0.name == "project" })?.value,
                  let projectID = UUID(uuidString: value) else { return nil }
            return .startFocus(projectID: projectID)
        case "timer":
            guard components.path.isEmpty, components.query == nil else { return nil }
            return .timer
        case "thoughts":
            guard components.path == "/new" else { return nil }
            guard components.query != nil else { return .captureThought(sessionID: nil) }
            guard let items = components.queryItems, items.count == 1,
                  items[0].name == "session", let value = items[0].value,
                  let sessionID = UUID(uuidString: value) else { return nil }
            return .captureThought(sessionID: sessionID)
        case "plan":
            guard components.path == "/next", let items = components.queryItems, items.count == 1,
                  items[0].name == "project", let value = items[0].value,
                  let projectID = UUID(uuidString: value) else { return nil }
            return .planNextSession(projectID: projectID)
        case "projects":
            guard components.path == "/new", components.query == nil else { return nil }
            return .newProject
        default:
            return nil
        }
    }

    func url(for route: AppRoute) -> URL {
        var components = URLComponents()
        components.scheme = scheme.rawValue
        switch route {
        case .startFocus(let projectID):
            components.host = "focus"
            components.queryItems = [URLQueryItem(name: "project", value: projectID.uuidString),
                                     URLQueryItem(name: "action", value: "start")]
        case .timer:
            components.host = "timer"
        case .captureThought(let sessionID):
            components.host = "thoughts"
            components.path = "/new"
            if let sessionID {
                components.queryItems = [URLQueryItem(name: "session", value: sessionID.uuidString)]
            }
        case .planNextSession(let projectID):
            components.host = "plan"
            components.path = "/next"
            components.queryItems = [URLQueryItem(name: "project", value: projectID.uuidString)]
        case .newProject:
            components.host = "projects"
            components.path = "/new"
        }
        // Each component is a fixed route name or a UUID, so URL construction
        // cannot fail on user-entered text.
        return components.url!
    }
}
