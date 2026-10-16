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
    @State private var exporting = false
    @State private var importing = false
    @State private var backupDocument = BackupDocument(data: Data())
    @State private var pendingRestore: AppSnapshot?
    @State private var confirmingRestore = false
    @State private var backupMessage: String?

    private func setting<Value>(_ path: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(get: { store.state.settings[keyPath: path] }, set: { value in
            store.update { state in
                state.settings[keyPath: path] = value
                if path == \Settings.longBreakInterval { state.completedInCycle = 0 }
            }
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily focus goal") {
                    Picker("Hours", selection: Binding(get: { store.state.settings.dailyGoalMinutes / 60 }, set: { hours in
                        store.update { $0.settings.dailyGoalMinutes = max(1, min(1440, hours * 60 + $0.settings.dailyGoalMinutes % 60)) }
                    })) { ForEach(0...24, id: \.self) { Text("\($0) hr").tag($0) } }
                    Picker("Minutes", selection: Binding(get: { store.state.settings.dailyGoalMinutes % 60 }, set: { minutes in
                        store.update { $0.settings.dailyGoalMinutes = max(1, min(1440, $0.settings.dailyGoalMinutes / 60 * 60 + minutes)) }
                    })) { ForEach(0...59, id: \.self) { Text("\($0) min").tag($0) } }
                        .disabled(store.state.settings.dailyGoalMinutes == 1440)
                }
                Section {
                    MinutePicker(title: "Focus", value: setting(\.defaultFocusMinutes), range: 10...60)
                    MinutePicker(title: "Short break", value: setting(\.defaultShortBreakMinutes), range: 1...60)
                    MinutePicker(title: "Long break", value: setting(\.defaultLongBreakMinutes), range: 1...60)
                } header: { Label("New project defaults", systemImage: "timer") } footer: { Text("Existing projects keep their own durations.") }
                Section {
                    Picker("Long break after", selection: setting(\.longBreakInterval)) {
                        ForEach(1...12, id: \.self) { Text("\($0) completed sessions").tag($0) }
                    }
                    .disabled(store.state.activeTimer != nil)
                    LabeledContent("Cycle progress", value: "\(store.state.completedInCycle) completed")
                } header: { Label("Break cycle", systemImage: "cup.and.saucer") } footer: {
                    Text("Completed focus sessions count across projects. Changing the interval resets the cycle. Each focus and break starts manually.")
                }
                Section {
                    Toggle("Notification sound", isOn: setting(\.notificationSound))
                    Toggle("Completion haptics", isOn: setting(\.haptics))
                    Button("Notification Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } header: { Label("Alerts", systemImage: "bell") } footer: {
                    Text("Sound changes apply to the next timer. Haptics play when the app is open. Notifications follow your iPhone's notification settings.")
                }
                Section("Appearance") {
                    Picker("Appearance", selection: setting(\.appearance)) {
                        ForEach(Appearance.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
                Section {
                    Button("Export Backup") {
                        do {
                            backupDocument = BackupDocument(data: try BackupService.encode(store.state))
                            exporting = true
                        } catch { store.errorMessage = error.localizedDescription }
                    }
                    Button("Restore Backup") { importing = true }
                } header: { Label("Backup", systemImage: "externaldrive") } footer: {
                    Text("Save a backup to Files or iCloud Drive. Restoring replaces all projects, history, and settings. End the timer before exporting or restoring.")
                }
                .disabled(store.state.activeTimer != nil)
                Section { Text("Your data stays on this device unless you export a backup.").foregroundStyle(.secondary) }
            }
            .navigationTitle("Settings")
            .fileExporter(isPresented: $exporting, document: backupDocument, contentType: .json,
                defaultFilename: "Pomodoro-Backup") { result in
                switch result {
                case .success: backupMessage = "Backup exported."
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
                Button("Replace with Backup", role: .destructive) {
                    if let pendingRestore, store.restore(pendingRestore) { backupMessage = "Backup restored." }
                    pendingRestore = nil
                }
                Button("Cancel", role: .cancel) { pendingRestore = nil }
            } message: {
                Text("Restore \(pendingRestore?.projects.count ?? 0) projects and \(pendingRestore?.sessions.count ?? 0) sessions. Current data will be replaced.")
            }
            .alert("Backup", isPresented: Binding(get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } })) {
                Button("OK") { backupMessage = nil }
            } message: { Text(backupMessage ?? "") }
        }
    }
}
