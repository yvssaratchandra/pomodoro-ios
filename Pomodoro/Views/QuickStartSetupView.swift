import SwiftUI

struct QuickStartSetupView: View {
    @Bindable var store: AppStore
    @State private var projectID: UUID?
    @State private var copiedMessage: String?
    @FocusState private var launchURLFocused: Bool
    @AppStorage("quickStart.liveContainerLaunchURL") private var copiedLaunchURL = ""
    @AppStorage("quickStart.useLiveContainer") private var useLiveContainer = true

    init(store: AppStore, projectID: UUID? = nil) {
        self.store = store
        _projectID = State(initialValue: projectID)
    }

    private var projects: [Project] { store.state.projects.filter { $0.status == .ongoing } }
    private var project: Project? { projects.first { $0.id == projectID } }
    private var isContainer: Bool {
        #if NATIVE_INTEGRATIONS
        false
        #else
        useLiveContainer
        #endif
    }
    private var launch: LiveContainerLaunchURL? {
        guard let url = URL(string: copiedLaunchURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return try? LiveContainerLaunchURL(url)
    }
    private var shortcutURL: URL? {
        guard let project else { return nil }
        let guest = AppURLRouter(scheme: AppInstallation.scheme).url(for: .startFocus(projectID: project.id))
        return isContainer ? launch?.url(forwarding: guest) : guest
    }

    var body: some View {
        Form {
            #if NATIVE_INTEGRATIONS
            Section("Home Screen widget") {
                Text("Add the Pomodoro widget from your iPhone's widget gallery, then choose a project. The widget opens Pomodoro to start focus.")
            }
            #endif
            Section("1. Choose a project") {
                Picker("Project", selection: $projectID) {
                    Text("Choose a project").tag(Optional<UUID>.none)
                    ForEach(projects) { Text($0.name).tag(Optional($0.id)) }
                }
                .accessibilityIdentifier("quickstart.project")
                if let project {
                    Text("Starts \(project.preferredFocusMinutes) min of focus.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Create an active project to use a shortcut.").foregroundStyle(.secondary)
                }
            }
            #if !NATIVE_INTEGRATIONS
            Section {
                Toggle("Use LiveContainer", isOn: $useLiveContainer)
                    .accessibilityIdentifier("quickstart.useContainer")
                if isContainer {
                    TextField("LiveContainer launch URL", text: $copiedLaunchURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($launchURLFocused)
                        .submitLabel(.done)
                        .onSubmit { launchURLFocused = false }
                        .accessibilityIdentifier("quickstart.launchURL")
                    if !copiedLaunchURL.isEmpty && launch == nil {
                        Text("Paste the launch URL copied from Pomodoro's LiveContainer menu.")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("quickstart.invalidURL")
                    }
                }
            } header: {
                Text("2. Connect LiveContainer")
            } footer: {
                if isContainer { Text("In LiveContainer, open Pomodoro's menu and choose Add to Home Screen, then Copy Launch URL.") }
            }
            #endif
            Section(isContainer ? "3. Add to Shortcuts" : "2. Add to Shortcuts") {
                if let shortcutURL {
                    Button("Copy shortcut link") { copy(shortcutURL, message: "Shortcut link copied.") }
                        .accessibilityIdentifier("quickstart.copy")
                    ShareLink("Share shortcut link", item: shortcutURL)
                    Button("Test shortcut") { UIApplication.shared.open(shortcutURL) }
                }
                Text("In Shortcuts, add Open URLs and paste the link. You can add that shortcut to your Home Screen.")
                    .foregroundStyle(.secondary)
                if shortcutURL != nil {
                    Text("Test shortcut starts focus when no timer is running. If a timer is running, it opens that timer.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let copiedMessage {
                    Text(copiedMessage).foregroundStyle(.secondary)
                        .accessibilityIdentifier("quickstart.copied")
                }
            }
            Section {
                NavigationLink("Troubleshooting") { QuickStartTroubleshootingView(store: store) }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Widgets & shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if projectID == nil { projectID = projects.first?.id } }
        .onChange(of: projectID) { _, _ in copiedMessage = nil }
        .onChange(of: copiedLaunchURL) { _, _ in copiedMessage = nil }
        .onChange(of: useLiveContainer) { _, _ in copiedMessage = nil }
    }

    private func copy(_ url: URL, message: String) {
        launchURLFocused = false
        UIPasteboard.general.string = url.absoluteString
        copiedMessage = message
    }
}

struct QuickStartTroubleshootingView: View {
    let store: AppStore
    @State private var copied = false
    @AppStorage("quickStart.liveContainerLaunchURL") private var copiedLaunchURL = ""

    private var launch: LiveContainerLaunchURL? {
        guard let url = URL(string: copiedLaunchURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return try? LiveContainerLaunchURL(url)
    }

    var body: some View {
        Form {
            #if NATIVE_INTEGRATIONS
            Section("Widgets") {
                Text("Add the Pomodoro widget from your iPhone's widget gallery, then select a project.")
            }
            #else
            Section("LiveContainer") {
                Text("If the shortcut opens Pomodoro without starting focus, create a Shortcut with Open URLs using the app-launch link below. Then tap Start Focus in Pomodoro.")
                if let launch {
                    Button("Copy app-launch link") {
                        UIPasteboard.general.string = launch.launchURL.absoluteString
                        copied = true
                    }
                    .accessibilityIdentifier("quickstart.fallback")
                    if copied { Text("App-launch link copied.").foregroundStyle(.secondary) }
                }
                Text("Check the shortcut while Pomodoro is closed and while it is open.")
                    .foregroundStyle(.secondary)
            }
            Section("About shortcut links") {
                Text("The saved LiveContainer launch link stays on this device and is not included in backups. If you reinstall LiveContainer, copy a new launch link.")
            }
            #endif
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Troubleshooting")
    }
}
