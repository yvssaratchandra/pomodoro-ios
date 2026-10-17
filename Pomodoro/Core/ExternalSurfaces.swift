import Foundation

struct WidgetSnapshot: Codable, Equatable {
    static let currentFormatVersion = 1

    struct Project: Codable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let preferredFocusMinutes: Int
    }

    struct Timer: Codable, Equatable, Identifiable {
        let id: UUID
        let kind: TimerKind
        let projectName: String
        let startedAt: Date
        let deadline: Date
    }

    let formatVersion: Int
    let generatedAt: Date
    let projects: [Project]
    let activeTimer: Timer?

    init(state: AppSnapshot, now: Date) {
        formatVersion = Self.currentFormatVersion
        generatedAt = now
        projects = state.projects.filter { $0.status == .ongoing }.map {
            Project(id: $0.id, name: $0.name, preferredFocusMinutes: $0.preferredFocusMinutes)
        }
        activeTimer = state.activeTimer.map { timer in
            Timer(id: timer.id, kind: timer.kind,
                  projectName: state.projects.first { $0.id == timer.projectID }?.name ?? "Project",
                  startedAt: timer.startedAt, deadline: timer.deadline)
        }
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
        case .newProject:
            components.host = "projects"
            components.path = "/new"
        }
        // Each component is a fixed route name or a UUID, so URL construction
        // cannot fail on user-entered text.
        return components.url!
    }
}
