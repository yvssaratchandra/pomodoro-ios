import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw AppError.invalid("Unable to read backup.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct SettingsView: View {
    @Bindable var store: AppStore
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Form {
            Section {
                NavigationLink { ProjectsView(store: store, navigation: navigation) } label: {
                    SettingsRowLabel(title: "Projects", icon: "folder")
                }
            }
            Section("Preferences") {
                NavigationLink { TimerDefaultsView(store: store) } label: {
                    SettingsRowLabel(title: "Timer defaults", icon: "timer")
                }
                NavigationLink { SoundSettingsView(store: store) } label: {
                    SettingsRowLabel(title: "Sounds & haptics", icon: "bell")
                }
                NavigationLink { AppearanceSettingsView(store: store) } label: {
                    SettingsRowLabel(title: "Appearance", icon: "paintpalette")
                }
            }
            Section("Access") {
                NavigationLink { QuickStartSetupView(store: store) } label: {
                    SettingsRowLabel(title: QuickStartSetupView.title, icon: "square.grid.2x2")
                }
                .accessibilityIdentifier("settings.quickstart")
                #if NATIVE_INTEGRATIONS
                NavigationLink { LockScreenPrivacyView(store: store) } label: {
                    SettingsRowLabel(title: "Lock Screen privacy", icon: "lock.shield")
                }
                #endif
            }
            Section("Data & support") {
                NavigationLink { BackupSettingsView(store: store) } label: {
                    SettingsRowLabel(title: "Backup & restore", icon: "externaldrive")
                }
                NavigationLink { SettingsHelpView(store: store) } label: {
                    SettingsRowLabel(title: "Help", icon: "questionmark.circle")
                }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Settings")
    }
}

private struct SettingsRowLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Color.indigo)
                .accessibilityHidden(true)
        }
    }
}

private func settingsBinding<Value>(_ store: AppStore, _ path: WritableKeyPath<Settings, Value>) -> Binding<Value> {
    Binding(get: { store.state.settings[keyPath: path] }, set: { value in
        store.update { state in
            state.settings[keyPath: path] = value
            if path == \.longBreakInterval { state.completedInCycle = 0 }
        }
    })
}

private struct TimerDefaultsView: View {
    @Bindable var store: AppStore
    var body: some View {
        Form {
            Section("New projects") {
                MinutePicker(title: "Focus", value: settingsBinding(store, \.defaultFocusMinutes), range: 10...60)
                MinutePicker(title: "Short break", value: settingsBinding(store, \.defaultShortBreakMinutes), range: 1...60)
                MinutePicker(title: "Long break", value: settingsBinding(store, \.defaultLongBreakMinutes), range: 1...60)
            }
            Section {
                Picker("Long break after", selection: settingsBinding(store, \.longBreakInterval)) {
                    ForEach(1...12, id: \.self) { Text("\($0) focus sessions").tag($0) }
                }
                .disabled(store.state.activeTimer != nil)
                LabeledContent("Completed in cycle", value: "\(store.state.completedInCycle)")
            } header: {
                Text("Break cycle")
            } footer: {
                Text("Changing the interval resets the cycle. Breaks start manually.")
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Timer defaults")
    }
}

private struct SoundSettingsView: View {
    @Bindable var store: AppStore
    private var enabled: Binding<Bool> {
        Binding(get: { store.state.settings.notificationSound }, set: { _ = store.updateCompletionAudio(enabled: $0) })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Completion sounds", isOn: enabled)
                if store.state.settings.notificationSound {
                    NavigationLink {
                        CompletionSoundSelectionView(store: store, kind: .focus)
                    } label: {
                        LabeledContent("Focus sound", value: store.state.settings.completionSound(for: .focus).title)
                    }
                    NavigationLink {
                        CompletionSoundSelectionView(store: store, kind: .shortBreak)
                    } label: {
                        LabeledContent("Break sound", value: store.state.settings.completionSound(for: .shortBreak).title)
                    }
                }
                Toggle("Haptics", isOn: settingsBinding(store, \.haptics))
            } footer: {
                Text("Uses your iPhone's alert volume and notification settings.")
            }
            Section {
                Button("Open notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Sounds & haptics")
    }
}

private struct CompletionSoundSelectionView: View {
    @Bindable var store: AppStore
    let kind: TimerKind
    @State private var testMessage: String?

    private var selection: CompletionSound {
        kind == .focus ? store.state.settings.focusCompletionSound : store.state.settings.breakCompletionSound
    }
    private var supported: [CompletionSound] {
        CompletionSound.allCases.filter { $0.filename == nil || CompletionSound.customSoundsSupported }
    }
    private var importedFallback: Bool {
        !CompletionSound.customSoundsSupported && selection.filename != nil
    }
    private func isEffectiveSelection(_ sound: CompletionSound) -> Bool {
        selection == sound || (importedFallback && sound == .systemDefault)
    }
    private var title: String { kind == .focus ? "Focus sound" : "Break sound" }

    var body: some View {
        Form {
            Section {
                ForEach(supported) { sound in
                    Button {
                        if store.updateCompletionAudio(kind: kind, sound: sound) { testMessage = nil }
                    } label: {
                        HStack {
                            Text(sound.title).foregroundStyle(.primary)
                            Spacer()
                            if isEffectiveSelection(sound) { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                    }
                    .accessibilityAddTraits(isEffectiveSelection(sound) ? [.isSelected] : [])
                }
            } footer: {
                if importedFallback {
                    Text("An imported sound is saved. This installation uses System Default until you choose another sound.")
                }
            }
            Section {
                Button("Preview") {
                    Task { testMessage = await store.testCompletionAlert(kind: kind) }
                }
                if let testMessage { Text(testMessage).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle(title)
    }
}

private struct AppearanceSettingsView: View {
    @Bindable var store: AppStore
    var body: some View {
        Form {
            Picker("Appearance", selection: settingsBinding(store, \.appearance)) {
                ForEach(Appearance.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Appearance")
    }
}

#if NATIVE_INTEGRATIONS
private struct LockScreenPrivacyView: View {
    @Bindable var store: AppStore
    var body: some View {
        Form {
            Toggle("Show project name", isOn: settingsBinding(store, \.showProjectNameOnLockScreen))
            Toggle("Show session text", isOn: settingsBinding(store, \.showIntentionOnLockScreen))
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Lock Screen privacy")
    }
}
#endif

private struct BackupSettingsView: View {
    @Bindable var store: AppStore
    @State private var exporting = false
    @State private var importing = false
    @State private var backupDocument = BackupDocument(data: Data())
    @State private var pendingRestore: AppSnapshot?
    @State private var confirmingRestore = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Button("Export backup") {
                    do {
                        let snapshot = store.state
                        backupDocument = BackupDocument(data: try BackupService.exportSavedData(snapshot))
                        exporting = true
                    } catch { store.errorMessage = error.localizedDescription }
                }
            } footer: {
                if store.state.activeTimer != nil {
                    Text("The running session isn’t included. Saved thoughts are included.")
                }
            }
            Section {
                Button("Restore backup") { importing = true }
                    .disabled(store.state.activeTimer != nil)
            } footer: {
                Text("End the timer before restoring a backup. Restoring replaces all app data.")
            }
            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            Section { Text("Your data stays on this device unless you export a backup.").foregroundStyle(.secondary) }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Backup & restore")
        .fileExporter(isPresented: $exporting, document: backupDocument, contentType: .json,
            defaultFilename: "Pomodoro-Backup") { result in
            switch result {
            case .success: message = "Backup exported."
            case .failure(let error): store.errorMessage = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 50_000_000 else { throw AppError.invalid("The backup exceeds the 50 MB limit.") }
                pendingRestore = try BackupService.decode(Data(contentsOf: url))
                confirmingRestore = true
            } catch { store.errorMessage = error.localizedDescription }
        }
        .confirmationDialog("Replace all app data?", isPresented: $confirmingRestore, titleVisibility: .visible) {
            Button("Replace with backup", role: .destructive) {
                if let pendingRestore, store.restore(pendingRestore) { message = "Backup restored." }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Restore \(pendingRestore?.projects.count ?? 0) projects and \(pendingRestore?.sessions.count ?? 0) sessions. Current data will be replaced.")
        }
    }
}

private struct SettingsHelpView: View {
    let store: AppStore
    var body: some View {
        Form {
            Section("Timers") {
                Text("Focus and breaks start manually. A completed focus session advances the break cycle.")
            }
            Section("Sounds") {
                Text("System Default uses your iPhone's default alert. It does not select a specific Messages tone. Silent mode, Focus, alert volume, and notification permissions affect playback.")
                if !CompletionSound.customSoundsSupported {
                    Text("This installation supports System Default and Silent. Imported custom choices are preserved in backups and play as System Default here.")
                }
            }
            Section("Shortcuts") {
                NavigationLink(QuickStartSetupView.helpTitle) { QuickStartTroubleshootingView(store: store) }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Help")
    }
}
