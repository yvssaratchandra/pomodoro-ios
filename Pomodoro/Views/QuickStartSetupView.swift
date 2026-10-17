import SwiftUI

struct QuickStartSetupView: View {
    @Bindable var store: AppStore
    @Environment(AppNavigation.self) private var navigation
    @State private var projectID: UUID?
    @State private var copiedMessage: String?
    @State private var thoughtLinkCopied = false
    @AppStorage("quickStart.liveContainerLaunchURL") private var savedLaunchURL = ""
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
        guard let url = URL(string: savedLaunchURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return try? LiveContainerLaunchURL(url)
    }
    private var shortcutURL: URL? {
        guard let project else { return nil }
        let guest = AppURLRouter(scheme: AppInstallation.scheme).url(for: .startFocus(projectID: project.id))
        return isContainer ? launch?.url(forwarding: guest) : guest
    }

    private var thoughtShortcutURL: URL? {
        let guest = AppURLRouter(scheme: AppInstallation.scheme).url(for: .captureThought(sessionID: nil))
        return isContainer ? launch?.url(forwarding: guest) : guest
    }

    var body: some View {
        Form {
            #if NATIVE_INTEGRATIONS
            if let error = store.widgetUpdateError {
                Section("Widget connection") {
                    Text("Widgets couldn’t update. Your data is saved.").foregroundStyle(.secondary)
                    Button("Retry") { store.refreshExternalSurfaces() }
                    DisclosureGroup("Connection details") {
                        let details = SharedWidgetContainer.diagnostics()
                        LabeledContent("Configured group", value: details.configuredGroup ?? "Missing")
                        LabeledContent("Declared groups", value: details.declaredGroups.joined(separator: "\n"))
                        LabeledContent("Selected group", value: details.selectedGroup ?? "None")
                        Text(details.failure ?? error).foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }
            Section("Home Screen widget") {
                Text("Add the Pomodoro widget from your iPhone's widget gallery, then choose a project.")
                    .foregroundStyle(.secondary)
            }
            #endif
            Section {
                if projects.isEmpty {
                    Text("Create an active project before making a shortcut.")
                        .foregroundStyle(.secondary)
                    Button("Go to Focus") { navigation.showFocus() }
                } else {
                    Picker("Project", selection: $projectID) {
                        Text("Choose a project").tag(Optional<UUID>.none)
                        ForEach(projects) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .accessibilityIdentifier("quickstart.project")
                    if let project {
                        LabeledContent("Focus duration", value: "\(project.preferredFocusMinutes) min")
                    }
                }
            } header: { Text("Project") }
            #if !NATIVE_INTEGRATIONS
            Section {
                NavigationLink {
                    QuickStartConnectionView()
                } label: {
                    HStack {
                        Text("Connection settings")
                        Spacer()
                        if isContainer && launch != nil { Text("Launch link saved").foregroundStyle(.secondary) }
                    }
                }
                .accessibilityIdentifier("quickstart.connection")
                if isContainer && launch == nil {
                    Text("Connect LiveContainer once to create a shortcut link.")
                        .foregroundStyle(.secondary)
                }
            }
            #endif
            if let shortcutURL {
                Section {
                    Button("Copy shortcut link") { copy(shortcutURL) }
                        .accessibilityIdentifier("quickstart.copy")
                    if let copiedMessage {
                        Text(copiedMessage).foregroundStyle(.secondary)
                            .accessibilityIdentifier("quickstart.copied")
                    }
                } footer: {
                    Text("In Shortcuts, add Open URLs, paste the link, then add the shortcut to your Home Screen.")
                }
                Section {
                    ShareLink("Share shortcut link", item: shortcutURL)
                    Button("Test shortcut") { UIApplication.shared.open(shortcutURL) }
                    Text("Test starts focus when idle. A running timer opens instead.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                if let thoughtShortcutURL {
                    Button("Copy Add thought link") {
                        UIPasteboard.general.string = thoughtShortcutURL.absoluteString
                        thoughtLinkCopied = true
                    }
                    .accessibilityIdentifier("quickstart.thought.copy")
                    Button("Test Add thought") { UIApplication.shared.open(thoughtShortcutURL) }
                        .accessibilityIdentifier("quickstart.thought.test")
                    if thoughtLinkCopied { Text("Add thought link copied.").foregroundStyle(.secondary) }
                } else {
                    Text("Connect LiveContainer above to create an Add thought link.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Add thought")
            } footer: {
                Text("In Shortcuts, add Open URLs and paste this link. Name it Add thought and add it to your Home Screen. It opens capture for your current focus session, or a new unassigned thought when idle or on a break.")
            }
            Section {
                NavigationLink("Troubleshooting") { QuickStartTroubleshootingView(store: store) }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Widgets & shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if projectID == nil { projectID = projects.first?.id } }
        .onChange(of: projectID) { _, _ in copiedMessage = nil }
        .onChange(of: savedLaunchURL) { _, _ in copiedMessage = nil; thoughtLinkCopied = false }
        .onChange(of: useLiveContainer) { _, _ in copiedMessage = nil; thoughtLinkCopied = false }
    }

    private func copy(_ url: URL) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        UIPasteboard.general.string = url.absoluteString
        copiedMessage = "Shortcut link copied."
    }
}

private struct QuickStartConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("quickStart.liveContainerLaunchURL") private var savedLaunchURL = ""
    @AppStorage("quickStart.useLiveContainer") private var useLiveContainer = true
    @State private var draftURL: String
    @State private var draftUseLiveContainer: Bool
    @State private var attemptedSave = false
    @FocusState private var urlFocused: Bool

    init() {
        _draftURL = State(initialValue: UserDefaults.standard.string(forKey: "quickStart.liveContainerLaunchURL") ?? "")
        _draftUseLiveContainer = State(initialValue: UserDefaults.standard.object(forKey: "quickStart.useLiveContainer") as? Bool ?? true)
    }

    private var validLaunch: LiveContainerLaunchURL? {
        guard let url = URL(string: draftURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return try? LiveContainerLaunchURL(url)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use LiveContainer", isOn: $draftUseLiveContainer)
                    .accessibilityIdentifier("quickstart.useContainer")
            }
            if draftUseLiveContainer {
                Section {
                    TextField("LiveContainer launch URL", text: $draftURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($urlFocused)
                        .submitLabel(.done)
                        .onSubmit { urlFocused = false }
                        .accessibilityIdentifier("quickstart.launchURL")
                    if attemptedSave && validLaunch == nil {
                        Text("Paste the launch URL copied from Pomodoro's LiveContainer menu.")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("quickstart.invalidURL")
                    }
                } header: {
                    Text("Launch link")
                } footer: {
                    Text("In LiveContainer, open Pomodoro's menu, choose Add to Home Screen, then Copy Launch URL.")
                }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Connection settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    attemptedSave = true
                    guard !draftUseLiveContainer || validLaunch != nil else { return }
                    if draftUseLiveContainer { savedLaunchURL = draftURL.trimmingCharacters(in: .whitespacesAndNewlines) }
                    useLiveContainer = draftUseLiveContainer
                    urlFocused = false
                    dismiss()
                }
                .accessibilityIdentifier("quickstart.connection.save")
            }
        }
        .onChange(of: draftURL) { _, _ in attemptedSave = false }
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
