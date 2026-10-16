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
            .toolbarBackground(AppTheme.background, for: .navigationBar, .tabBar)
            .toolbarBackground(colorScheme == .dark ? .visible : .automatic, for: .navigationBar, .tabBar)
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
            let config = ModelConfiguration(isStoredInMemoryOnly: testing, cloudKitDatabase: .none)
            let container = try ModelContainer(for: AppDocument.self, configurations: config)
            loadedStore = try AppStore(container: container)
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
    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selectedTab) {
            FocusView(store: store, navigation: navigation)
                .tabItem { Label("Focus", systemImage: "timer") }.tag(AppNavigation.Tab.focus)
            StatsView(store: store).tabItem { Label("Stats", systemImage: "chart.bar") }.tag(AppNavigation.Tab.stats)
            ProjectsView(store: store, navigation: navigation)
                .tabItem { Label("Projects", systemImage: "folder") }.tag(AppNavigation.Tab.projects)
            SettingsView(store: store).tabItem { Label("Settings", systemImage: "gearshape") }.tag(AppNavigation.Tab.settings)
        }
        .onOpenURL { navigation.receive($0) }
        .safeAreaInset(edge: .bottom) { UndoBanner(store: store) }
        .onChange(of: store.pendingSessionDeletion?.sessions.count) { _, count in
            if let count { UIAccessibility.post(notification: .announcement, argument: "\(count) sessions deleted. Undo available.") }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.reconcile()
            store.refreshExternalSurfaces()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            store.refreshExternalSurfaces()
        }
        .sheet(isPresented: $navigation.showingProjectCreation) { ProjectEditor(store: store, project: nil) }
        .alert("Quick Start", isPresented: Binding(get: { navigation.message != nil }, set: { if !$0 { navigation.message = nil } })) {
            Button("OK", role: .cancel) { navigation.message = nil }
        } message: { Text(navigation.message ?? "") }
        .preferredColorScheme(store.state.settings.appearance == .system ? nil : store.state.settings.appearance == .dark ? .dark : .light)
        .alert("Unable to Complete Action", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .task {
            navigation.connect(to: store)
            store.reconcile()
            if store.state.activeTimer != nil { store.scheduleNotification() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                store.expireSessionUndo()
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
