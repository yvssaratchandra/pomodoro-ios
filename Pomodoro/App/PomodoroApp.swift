import SwiftUI
import SwiftData

enum AppTheme {
    static let breakAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 132 / 255, green: 160 / 255, blue: 140 / 255, alpha: 1)
            : UIColor(red: 78 / 255, green: 107 / 255, blue: 86 / 255, alpha: 1)
    })
    static let breakButtonForeground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .systemGroupedBackground
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .secondarySystemGroupedBackground
    })
}

private struct AppScreen: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(AppTheme.background.ignoresSafeArea())
            .toolbarBackground(AppTheme.background, for: .tabBar)
            .toolbarBackground(colorScheme == .dark ? .visible : .automatic, for: .tabBar)
    }
}

extension View {
    func appScreen() -> some View { modifier(AppScreen()) }
}

@main struct PomodoroApp: App {
    @State private var store: AppStore? = nil
    private let startupError: String?

    init() {
        var loadedStore: AppStore?
        var loadError: String?
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            let config: ModelConfiguration
            if testing, let identifier = ProcessInfo.processInfo.environment["POMODORO_TEST_STORE_ID"],
               let id = UUID(uuidString: identifier) {
                // A unique temporary store lets launch tests verify recovery across processes.
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(id.uuidString).store")
                config = ModelConfiguration(url: url, cloudKitDatabase: .none)
            } else {
                config = ModelConfiguration(isStoredInMemoryOnly: testing, cloudKitDatabase: .none)
            }
            let container = try ModelContainer(for: AppDocument.self, configurations: config)
            loadedStore = try AppStore(container: container)
            if testing, ProcessInfo.processInfo.environment["POMODORO_TEST_SCENARIO"] == "break-ready" {
                let project = Project(name: "A long project name for layout checks")
                loadedStore?.update { state in
                    state.projects = [project]
                    try TimerEngine.startFocus(&state, projectID: project.id, minutes: 10,
                                               now: Date().addingTimeInterval(-601))
                }
            }
            if testing, ProcessInfo.processInfo.environment["POMODORO_TEST_SCENARIO"] == "project-goals" {
                let work = Project(name: "Work")
                let reading = Project(name: "Reading")
                let now = Date()
                loadedStore?.update { state in
                    state.projects = [work, reading]
                    state.sessions = [
                        FocusSession(id: UUID(), projectID: work.id, startedAt: now.addingTimeInterval(-1200),
                                     endedAt: now.addingTimeInterval(-600), plannedSeconds: 1200, outcome: .interrupted),
                        FocusSession(id: UUID(), projectID: reading.id, startedAt: now.addingTimeInterval(-600),
                                     endedAt: now.addingTimeInterval(-300), plannedSeconds: 600, outcome: .interrupted)
                    ]
                    try GoalEngine.setDaily(&state.goalPlan, projectID: work.id,
                                            minutes: Array(repeating: 240, count: 7), now: now)
                    try GoalEngine.setDaily(&state.goalPlan, projectID: reading.id,
                                            minutes: Array(repeating: 60, count: 7), now: now)
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
        _store = State(initialValue: loadedStore)
        startupError = loadError
    }

    var body: some Scene {
        WindowGroup {
            if let store {
                RootView(store: store)
            } else {
                ContentUnavailableView("Unable to Open Data", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Your stored data has not been replaced. Restart the app and try again.\n\n\(startupError ?? "Unknown error")"))
            }
        }
    }
}

struct RootView: View {
    @Bindable var store: AppStore
    @State private var navigation = AppNavigation(scheme: AppInstallation.scheme)
    @StateObject private var dimFocus = DimFocusCoordinator()
    @StateObject private var presentation = AppPresentationContext()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var testing: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    private var appearance: ColorScheme? {
        if testing, let value = ProcessInfo.processInfo.environment["POMODORO_TEST_APPEARANCE"] {
            return value == "dark" ? .dark : .light
        }
        return store.state.settings.appearance == .system ? nil : store.state.settings.appearance == .dark ? .dark : .light
    }
    var body: some View {
        configuredContent
            .task { await runLifecycle() }
            .background { AppPresentationProbe(context: presentation).allowsHitTesting(false) }
            .onChange(of: scenePhase) { _, _ in presentation.refresh() }
            .onChange(of: presentation.isActive) { _, active in
                if active {
                    store.reconcile()
                    store.refreshExternalSurfaces()
                }
                synchronizeDimFocus()
            }
    }

    private var tabs: some View {
        TabView(selection: Binding(get: { navigation.selectedTab }, set: { tab in
            if tab == .focus { navigation.showFocus() }
            else { navigation.selectedTab = tab }
        })) {
            FocusView(store: store, navigation: navigation, dimFocus: dimFocus, presentation: presentation)
                .safeAreaInset(edge: .bottom) { UndoBanner(store: store) }
                .tabItem { Label("Focus", systemImage: "timer") }.tag(AppNavigation.Tab.focus)
            ThoughtsView(store: store, navigation: navigation)
                .safeAreaInset(edge: .bottom) { UndoBanner(store: store) }
                .tabItem { Label("Thoughts", systemImage: "text.bubble") }.tag(AppNavigation.Tab.thoughts)
            StatsView(store: store).safeAreaInset(edge: .bottom) { UndoBanner(store: store) }.tabItem { Label("Stats", systemImage: "chart.bar") }.tag(AppNavigation.Tab.stats)
        }
    }

    private var dimPresentation: some View {
        tabs
            .accessibilityHidden(dimFocus.isDimmed)
            .allowsHitTesting(!dimFocus.isDimmed)
            .overlay {
                if dimFocus.isDimmed, let timer = store.state.activeTimer, timer.kind == .focus {
                    DimFocusView(timer: timer, reveal: dimFocus.reveal) {
                        navigation.requestThoughtCapture(context: ThoughtCaptureContext(
                            projectID: timer.projectID, originSessionID: timer.id))
                    }
                    .ignoresSafeArea()
                }
            }
            .statusBarHidden(dimFocus.isDimmed)
            .persistentSystemOverlays(dimFocus.isDimmed ? .hidden : .automatic)
            .onOpenURL { url in
                // An external link reveals the app rather than covering its destination.
                if dimFocus.isDimmed { dimFocus.reveal() }
                navigation.receive(url)
            }
    }

    private var dimChanges: some View {
        dimPresentation
            .onChange(of: store.state.activeTimer) { _, _ in synchronizeDimFocus() }
            .onChange(of: navigation.selectedTab) { _, _ in synchronizeDimFocus() }
            .onChange(of: navigation.focusPath) { _, _ in synchronizeDimFocus() }
            .onChange(of: navigation.capturePresentationBlockers) { _, _ in synchronizeDimFocus() }
            .onChange(of: navigation.thoughtCaptureContext?.id) { _, id in
                dimFocus.setBlocked("thought-capture", id != nil)
            }
    }

    private var accessibilityAndKeyboardEvents: some View {
        dimChanges
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in synchronizeDimFocus() }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in synchronizeDimFocus() }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in dimFocus.setBlocked("keyboard", true) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in dimFocus.setBlocked("keyboard", false) }
            .onChange(of: navigation.message) { _, _ in synchronizeDimFocus() }
            .onChange(of: store.errorMessage) { _, _ in synchronizeDimFocus() }
    }

    private var applicationEvents: some View {
        accessibilityAndKeyboardEvents
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in presentation.applicationBecameActive() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in presentation.applicationResignedActive() }
    }

    private var systemEvents: some View {
        applicationEvents
            .onChange(of: store.pendingDeletion?.count) { _, count in
                if count != nil, let pending = store.pendingDeletion {
                    UIAccessibility.post(notification: .announcement, argument: "\(pending.message). Undo available.")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                store.reconcile()
                store.refreshExternalSurfaces()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                store.refreshExternalSurfaces()
            }
    }

    private var capturePresentation: some View {
        @Bindable var navigation = navigation
        return systemEvents
            .sheet(isPresented: $navigation.showingProjectCreation, onDismiss: {
                navigation.setCapturePresentationBlocked(false, owner: "project-creation")
            }) { ProjectEditor(store: store, project: nil, createNew: true) }
            .sheet(item: $navigation.thoughtCaptureContext, onDismiss: captureDidDismiss) { context in
                ThoughtCaptureView(store: store, context: context)
            }
            .sheet(item: $navigation.nextSessionPlanProject, onDismiss: navigation.nextSessionPlanDidDismiss) { project in
                ProjectPlanEditor(store: store, projectID: project.id)
            }
            .onChange(of: navigation.showingProjectCreation) { _, showing in
                if showing { navigation.setCapturePresentationBlocked(true, owner: "project-creation") }
            }
            .environment(navigation)
    }

    private var configuredContent: some View {
        capturePresentation
            .alert("Quick Start", isPresented: quickStartAlertPresented) {
                Button("OK", role: .cancel) { navigation.message = nil }
            } message: { Text(navigation.message ?? "") }
            .preferredColorScheme(appearance)
            .environment(\.dynamicTypeSize, testing && ProcessInfo.processInfo.environment["POMODORO_TEST_DYNAMIC_TYPE"] == "accessibility2" ? .accessibility2 : dynamicTypeSize)
            .alert("Unable to Complete Action", isPresented: actionErrorAlertPresented) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }

    private var quickStartAlertPresented: Binding<Bool> {
        Binding<Bool>(
            get: { navigation.message != nil },
            set: { presented in
                if !presented { navigation.message = nil }
            })
    }

    private var actionErrorAlertPresented: Binding<Bool> {
        Binding<Bool>(
            get: { store.errorMessage != nil },
            set: { presented in
                if !presented { store.errorMessage = nil }
            })
    }

    private func runLifecycle() async {
        presentation.refresh()
        navigation.canPresentEditor = { [weak store, weak presentation] in
            presentation?.canPresent == true && store?.errorMessage == nil
        }
        navigation.connect(to: store)
        store.reconcile()
        synchronizeDimFocus()
        if store.state.activeTimer != nil { store.scheduleNotification() }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            presentation.refresh()
            navigation.resumePendingEditors()
            store.expireUndo()
            if presentation.isActive { store.reconcile() }
            synchronizeDimFocus()
        }
    }

    private func synchronizeDimFocus() {
        dimFocus.setBlocked("presentation", !navigation.capturePresentationBlockers.isEmpty ||
                            navigation.showingProjectCreation || navigation.message != nil || store.errorMessage != nil)
        // This catches sheets owned by nested screens, including Stats detail editors.
        dimFocus.setBlocked("external-sheet", navigation.thoughtCaptureContext == nil && presentation.hasPresentedContent)
        dimFocus.update(timer: store.state.activeTimer,
                        focusVisible: navigation.selectedTab == .focus && navigation.focusPath.isEmpty,
                        sceneActive: presentation.isActive,
                        accessibilityActive: UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning)
    }

    private func captureDidDismiss() {
        navigation.thoughtCaptureDidDismiss()
        dimFocus.setBlocked("thought-capture", navigation.thoughtCaptureContext != nil)
        synchronizeDimFocus()
    }

}
