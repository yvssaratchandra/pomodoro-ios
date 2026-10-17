import SwiftUI
import SwiftData

enum AppTheme {
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
                                               intention: "Finish the introduction", now: Date().addingTimeInterval(-601))
                }
            }
            if testing, ProcessInfo.processInfo.environment["POMODORO_TEST_SCENARIO"] == "saved-stats" {
                let writing = Project(name: "Writing")
                let study = Project(name: "Study")
                let now = Date()
                loadedStore?.update { state in
                    state.projects = [writing, study]
                    state.sessions = [FocusSession(id: UUID(), projectID: writing.id,
                        startedAt: now.addingTimeInterval(-1800), endedAt: now.addingTimeInterval(-300),
                        plannedSeconds: 1500, outcome: .completed)]
                    try TimerEngine.startFocus(&state, projectID: writing.id, minutes: 25,
                                               now: now.addingTimeInterval(-120))
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
        @Bindable var navigation = navigation
        TabView(selection: Binding(get: { navigation.selectedTab }, set: { tab in
            if tab == .focus { navigation.showFocus() }
            else { navigation.selectedTab = tab }
        })) {
            FocusView(store: store, navigation: navigation)
                .safeAreaInset(edge: .bottom) { UndoBanner(store: store) }
                .tabItem { Label("Focus", systemImage: "timer") }.tag(AppNavigation.Tab.focus)
            ThoughtsView(store: store, navigation: navigation)
                .safeAreaInset(edge: .bottom) { UndoBanner(store: store) }
                .tabItem { Label("Thoughts", systemImage: "text.bubble") }.tag(AppNavigation.Tab.thoughts)
            StatsView(store: store).safeAreaInset(edge: .bottom) { UndoBanner(store: store) }.tabItem { Label("Stats", systemImage: "chart.bar") }.tag(AppNavigation.Tab.stats)
        }
        .onOpenURL { navigation.receive($0) }
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
        .sheet(isPresented: $navigation.showingProjectCreation) { ProjectEditor(store: store, project: nil) }
        .environment(navigation)
        .alert("Quick Start", isPresented: Binding(get: { navigation.message != nil }, set: { if !$0 { navigation.message = nil } })) {
            Button("OK", role: .cancel) { navigation.message = nil }
        } message: { Text(navigation.message ?? "") }
        .preferredColorScheme(appearance)
        .environment(\.dynamicTypeSize, testing && ProcessInfo.processInfo.environment["POMODORO_TEST_DYNAMIC_TYPE"] == "accessibility2" ? .accessibility2 : dynamicTypeSize)
        .alert("Unable to Complete Action", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .task {
            navigation.connect(to: store)
            store.reconcile()
            if store.state.activeTimer != nil { store.scheduleNotification() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                store.expireUndo()
                if scenePhase == .active { store.reconcile() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.reconcile()
                store.refreshExternalSurfaces()
            }
        }
    }
}
