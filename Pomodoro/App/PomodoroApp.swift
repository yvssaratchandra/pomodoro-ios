import SwiftUI
import SwiftData

@main struct PomodoroApp: App {
    private let container: ModelContainer?
    @State private var store: AppStore? = nil
    private let startupError: String?

    init() {
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
            let config = ModelConfiguration(isStoredInMemoryOnly: testing, cloudKitDatabase: .none)
            let container = try ModelContainer(for: AppDocument.self, configurations: config)
            self.container = container
            _store = State(initialValue: try AppStore(container: container))
            startupError = nil
        } catch {
            container = nil
            startupError = error.localizedDescription
        }
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
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView {
            FocusView(store: store).tabItem { Label("Focus", systemImage: "timer") }
            StatsView(store: store).tabItem { Label("Stats", systemImage: "chart.bar") }
            ProjectsView(store: store).tabItem { Label("Projects", systemImage: "folder") }
            SettingsView(store: store).tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .preferredColorScheme(store.state.settings.appearance == .system ? nil : store.state.settings.appearance == .dark ? .dark : .light)
        .alert("Unable to Complete Action", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .task {
            store.reconcile()
            if store.state.activeTimer != nil { store.scheduleNotification() }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if scenePhase == .active { store.reconcile() }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.reconcile() } }
    }
}
