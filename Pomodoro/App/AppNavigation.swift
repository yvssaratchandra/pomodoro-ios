import Foundation
import Observation

enum AppInstallation {
    #if NATIVE_INTEGRATIONS
    static let scheme = AppURLScheme.native
    #else
    static let scheme = AppURLScheme.container
    #endif
}

@MainActor @Observable final class AppNavigation {
    enum Tab: Hashable { case focus, stats, projects, thoughts, settings }

    var selectedTab: Tab = .focus
    var selectedProjectID: UUID?
    var showingProjectCreation = false
    var message: String?
    var thoughtProjectFilter: ThoughtProjectFilter = .all
    var thoughtFilter = 0
    var thoughtSearch = ""
    private(set) var focusRequestID = UUID()
    private let router: AppURLRouter
    @ObservationIgnored private var store: AppStore?
    @ObservationIgnored private var pendingURLs: [URL] = []

    init(scheme: AppURLScheme) { router = AppURLRouter(scheme: scheme) }

    func showThoughts(projectID: UUID?) {
        thoughtProjectFilter = projectID.map(ThoughtProjectFilter.project) ?? .all
        thoughtFilter = 0
        thoughtSearch = ""
        selectedTab = .thoughts
    }

    func connect(to store: AppStore) {
        self.store = store
        let queued = pendingURLs
        pendingURLs.removeAll()
        for url in queued { receive(url) }
    }

    func receive(_ url: URL) {
        guard let store else { pendingURLs.append(url); return }
        guard let route = router.parse(url) else {
            message = "This Pomodoro link is not supported. Create a new shortcut in Settings."
            return
        }
        message = nil
        selectedTab = .focus
        showingProjectCreation = false
        focusRequestID = UUID()
        switch route {
        case .timer:
            store.reconcile()
            if let timer = store.state.activeTimer { selectedProjectID = timer.projectID }
        case .newProject:
            showingProjectCreation = true
        case .startFocus(let projectID):
            store.reconcile()
            if let timer = store.state.activeTimer {
                selectedProjectID = timer.projectID
                return
            }
            guard let project = store.state.projects.first(where: { $0.id == projectID }), project.status == .ongoing else {
                message = "This project is no longer available for focus. Choose an ongoing project."
                return
            }
            if store.startFocus(projectID: project.id, minutes: project.preferredFocusMinutes) {
                selectedProjectID = project.id
            }
        }
    }
}
