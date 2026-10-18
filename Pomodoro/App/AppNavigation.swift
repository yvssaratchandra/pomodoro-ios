import Foundation
import Observation

enum AppInstallation {
    #if NATIVE_INTEGRATIONS
    static let scheme = AppURLScheme.native
    #else
    static let scheme = AppURLScheme.container
    #endif
}

enum FocusDestination: Hashable { case projects, settings }

enum ThoughtStatusFilter: String, CaseIterable, Identifiable {
    case open = "Open", all = "All", done = "Done"
    var id: Self { self }

    func includes(_ thought: CapturedThought) -> Bool {
        switch self {
        case .open: thought.completedAt == nil
        case .all: true
        case .done: thought.completedAt != nil
        }
    }
}

@MainActor @Observable final class AppNavigation {
    enum Tab: Hashable { case focus, thoughts, stats }

    var selectedTab: Tab = .focus
    var focusPath: [FocusDestination] = []
    var selectedProjectID: UUID?
    var showingProjectCreation = false
    var message: String?
    var thoughtProjectFilter: ThoughtProjectFilter = .all
    var thoughtFilter: ThoughtStatusFilter = .open
    var thoughtSearch = ""
    var thoughtCaptureContext: ThoughtCaptureContext?
    var nextSessionPlanProject: Project?
    private(set) var captureRequestID = UUID()
    private(set) var capturePresentationBlockers: Set<String> = []
    private enum CaptureRequest {
        case session(UUID?)
        case context(ThoughtCaptureContext)
    }
    private enum EditorRequest {
        case capture(CaptureRequest)
        case plan(UUID)
    }
    @ObservationIgnored private var pendingEditor: EditorRequest?
    @ObservationIgnored var canPresentEditor: (() -> Bool)?
    private(set) var focusRequestID = UUID()
    private let router: AppURLRouter
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var store: AppStore?
    @ObservationIgnored private var pendingURLs: [URL] = []

    init(scheme: AppURLScheme, now: @escaping () -> Date = Date.init) {
        router = AppURLRouter(scheme: scheme)
        self.now = now
    }

    func showFocus() {
        selectedTab = .focus
        focusPath.removeAll()
        showingProjectCreation = false
        focusRequestID = UUID()
    }

    func showProjects() {
        selectedTab = .focus
        focusPath = [.projects]
    }

    func showSettings() {
        selectedTab = .focus
        focusPath = [.settings]
    }

    func showThoughts(projectID: UUID?) {
        thoughtProjectFilter = projectID.map(ThoughtProjectFilter.project) ?? .all
        thoughtFilter = .open
        thoughtSearch = ""
        selectedTab = .thoughts
    }

    func connect(to store: AppStore) {
        self.store = store
        let queued = pendingURLs
        pendingURLs.removeAll()
        for url in queued { receive(url) }
        presentPendingEditorIfPossible()
    }

    func receive(_ url: URL) {
        guard let store else { pendingURLs.append(url); return }
        guard let route = router.parse(url) else {
            message = "This Pomodoro link is not supported. Create a new shortcut in Settings."
            return
        }
        message = nil
        if case .captureThought(let sessionID) = route {
            requestThoughtCapture(sessionID: sessionID)
            return
        }
        if case .planNextSession(let projectID) = route {
            requestNextSessionPlan(projectID: projectID)
            return
        }
        showFocus()
        switch route {
        case .captureThought, .planNextSession:
            break
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


    /// A context is frozen when the composer is presented, so later timer changes
    /// cannot move a draft into another session.
    func requestThoughtCapture(context: ThoughtCaptureContext) {
        requestCapture(.context(context))
    }

    func requestThoughtCapture(sessionID: UUID? = nil) {
        requestCapture(.session(sessionID))
    }

    func setCapturePresentationBlocked(_ blocked: Bool, owner: String) {
        if blocked { capturePresentationBlockers.insert(owner) }
        else { capturePresentationBlockers.remove(owner) }
        presentPendingEditorIfPossible()
    }

    func thoughtCaptureDidDismiss() {
        thoughtCaptureContext = nil
        presentPendingEditorIfPossible()
    }

    private func requestCapture(_ request: CaptureRequest) {
        // Leave the existing view identity, text, and context intact.
        if thoughtCaptureContext != nil {
            captureRequestID = UUID()
            return
        }
        pendingEditor = .capture(request)
        presentPendingEditorIfPossible()
    }

    func resumePendingEditors() { presentPendingEditorIfPossible() }

    func requestNextSessionPlan(projectID: UUID) {
        if nextSessionPlanProject?.id == projectID { return }
        pendingEditor = .plan(projectID)
        presentPendingEditorIfPossible()
    }

    func nextSessionPlanDidDismiss() {
        nextSessionPlanProject = nil
        presentPendingEditorIfPossible()
    }

    private func presentPendingEditorIfPossible() {
        guard thoughtCaptureContext == nil, nextSessionPlanProject == nil, capturePresentationBlockers.isEmpty,
              canPresentEditor?() != false,
              let request = pendingEditor, let store else { return }
        switch request {
        case .plan(let projectID):
            guard let project = store.state.projects.first(where: { $0.id == projectID }) else {
                pendingEditor = nil
                message = "This project is no longer available."
                return
            }
            pendingEditor = nil
            showFocus()
            selectedProjectID = projectID
            nextSessionPlanProject = project
        case .capture(let capture):
            let context: ThoughtCaptureContext
            switch capture {
            case .context(let supplied): context = supplied
            case .session(let sessionID):
                store.reconcile()
                guard canPresentEditor?() != false else { return }
                context = Self.captureContext(in: store.state, sessionID: sessionID, now: now())
                showFocus()
            }
            pendingEditor = nil
            thoughtCaptureContext = context
            captureRequestID = UUID()
        }
    }

    static func captureContext(in state: AppSnapshot, sessionID: UUID?, now: Date) -> ThoughtCaptureContext {
        if let sessionID {
            if let timer = state.activeTimer, timer.id == sessionID, timer.kind == .focus, timer.deadline > now {
                return ThoughtCaptureContext(projectID: timer.projectID, originSessionID: timer.id)
            }
            if let session = state.sessions.first(where: { $0.id == sessionID }) {
                return ThoughtCaptureContext(projectID: session.projectID, originSessionID: session.id)
            }
        } else if let timer = state.activeTimer, timer.kind == .focus, timer.deadline > now {
            return ThoughtCaptureContext(projectID: timer.projectID, originSessionID: timer.id)
        }
        return ThoughtCaptureContext(projectID: nil, originSessionID: nil)
    }
}
