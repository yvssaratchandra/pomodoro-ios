import SwiftUI

struct QuickStartSetupView: View {
    @Bindable var store: AppStore
    @State private var projectID: UUID?
    @State private var copiedMessage: String?
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
            Group {
                Section {
                    Picker("Project", selection: $projectID) {
                        Text("Choose a project").tag(Optional<UUID>.none)
                        ForEach(projects) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .accessibilityIdentifier("quickstart.project")
                    if let project {
                        Text("Starts \(project.preferredFocusMinutes) minutes of focus for \(project.name). Uses the project's latest duration when opened.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Choose an ongoing project to create a shortcut.").foregroundStyle(.secondary)
                    }
                } header: { Text("Quick start") } footer: {
                    Text("If a timer is already running, the shortcut opens it without starting another session.")
                }
                #if !NATIVE_INTEGRATIONS
                Section {
                    Toggle("Use LiveContainer", isOn: $useLiveContainer)
                        .accessibilityIdentifier("quickstart.useContainer")
                } footer: {
                    Text("Turn this off if Pomodoro is installed directly on your iPhone.")
                }
                #endif
                if isContainer {
                    Section {
                        Text("In LiveContainer, open Pomodoro's menu, choose Add to Home Screen, then Copy Launch URL. Paste that URL below.")
                        TextField("LiveContainer launch URL", text: $copiedLaunchURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL)
                            .accessibilityIdentifier("quickstart.launchURL")
                        if !copiedLaunchURL.isEmpty && launch == nil {
                            Text("Paste Pomodoro's launch URL, including its bundle-name parameter.")
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("quickstart.invalidURL")
                        }
                    } header: { Text("Connect LiveContainer") } footer: {
                        Text("This device's launch URL stays here and is not included in backups.")
                    }
                }
                Section {
                    if let shortcutURL {
                        Button("Copy shortcut URL") { copy(shortcutURL, message: "Shortcut URL copied.") }
                            .accessibilityIdentifier("quickstart.copy")
                        ShareLink("Share shortcut URL", item: shortcutURL)
                    } else {
                        Button("Copy shortcut URL") {}.disabled(true)
                            .accessibilityIdentifier("quickstart.copy")
                    }
                    Text("In Shortcuts, create a shortcut with the Open URLs action and paste the copied URL. Add the shortcut to your Home Screen or a Shortcuts widget.")
                        .foregroundStyle(.secondary)
                    if let copiedMessage {
                        Text(copiedMessage).foregroundStyle(.secondary)
                            .accessibilityIdentifier("quickstart.copied")
                    }
                } header: { Text("Add to Shortcuts") }
                if isContainer, let launch {
                    Section {
                        Button("Copy app-launch URL") { copy(launch.launchURL, message: "App-launch URL copied.") }
                            .accessibilityIdentifier("quickstart.fallback")
                    } header: { Text("If quick start doesn't work") } footer: {
                        Text("Some LiveContainer versions may only open the app. Use this fallback URL with Open URLs, then tap Start Focus in Pomodoro. Check quick start while Pomodoro is closed and while it is already open.")
                    }
                }
            }.listRowBackground(AppTheme.surface)
        }
        .appScreen()
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Quick-start shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if projectID == nil { projectID = projects.first?.id }
        }
        .onChange(of: projectID) { _, _ in copiedMessage = nil }
        .onChange(of: copiedLaunchURL) { _, _ in copiedMessage = nil }
        .onChange(of: useLiveContainer) { _, _ in copiedMessage = nil }
    }

    private func copy(_ url: URL, message: String) {
        UIPasteboard.general.string = url.absoluteString
        copiedMessage = message
    }
}
