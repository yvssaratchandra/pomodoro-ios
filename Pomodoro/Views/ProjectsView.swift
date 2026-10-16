import SwiftUI

struct ProjectsView: View {
    @Bindable var store: AppStore
    @Bindable var navigation: AppNavigation
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                List {
                    Group {
                        if store.state.projects.isEmpty {
                            ContentUnavailableView {
                                Label("Your Projects", systemImage: "folder")
                            } description: {
                                Text("Give your focus a home. Create your first project to begin.")
                            } actions: {
                                Button("Create Project") { navigation.showingProjectCreation = true }
                            }
                        }
                        ForEach(ProjectStatus.allCases) { status in
                            let projects = store.state.projects.filter { $0.status == status }
                            if !projects.isEmpty {
                                Section(status.title) {
                                    ForEach(projects) { project in
                                        NavigationLink {
                                            ProjectDetail(store: store, projectID: project.id)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Label(project.name, systemImage: "folder.fill").font(.headline)
                                                Text("\(DurationText.work(Statistics.total(store.state, projectID: project.id, now: timeline.date))) total")
                                                    .font(.system(.subheadline, design: .rounded)).monospacedDigit()
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }.listRowBackground(AppTheme.surface)
                }.appScreen()
            }
            .navigationTitle("Projects")
            .toolbar { Button("New Project", systemImage: "plus") { navigation.showingProjectCreation = true }.accessibilityIdentifier("projects.new") }
        }
    }
}

struct ProjectDetail: View {
    @Bindable var store: AppStore
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var merging = false
    private var project: Project? { store.state.projects.first { $0.id == projectID } }

    var body: some View {
        Group {
            if let project {
                List {
                    Group {
                        Section("Project") {
                            LabeledContent("Status", value: project.status.title)
                            LabeledContent("Total focus", value: DurationText.work(Statistics.total(store.state, projectID: project.id, now: Date())))
                            LabeledContent("Focus session", value: "\(project.focusMinutes) min")
                            LabeledContent("Short break", value: "\(project.shortBreakMinutes) min")
                            LabeledContent("Long break", value: "\(project.longBreakMinutes) min")
                            Button("Edit Project") { editing = true }
                            NavigationLink("Create quick-start shortcut") {
                                QuickStartSetupView(store: store, projectID: project.id)
                            }
                            .disabled(project.status != .ongoing)
                            .accessibilityIdentifier("project.quickstart")
                        }
                        Section {
                            Button("Merge into Another Project") { merging = true }
                                .disabled(store.state.projects.count < 2 || store.state.activeTimer?.projectID == project.id)
                        } footer: {
                            Text("Merging transfers this project's history to another project and removes this project.")
                        }
                        Section("Session history") {
                            let sessions = store.state.sessions.filter { $0.projectID == project.id }.sorted { $0.startedAt > $1.startedAt }
                            if sessions.isEmpty { Text("No sessions yet").foregroundStyle(.secondary) }
                            ForEach(sessions) { session in
                                NavigationLink { SessionDetailView(store: store, sessionID: session.id) }
                                    label: { SessionRow(session: session, name: project.name) }
                            }
                        }
                    }.listRowBackground(AppTheme.surface)
                }
                .appScreen()
                .navigationTitle(project.name)
                .sheet(isPresented: $editing) { ProjectEditor(store: store, project: project) }
                .sheet(isPresented: $merging) { MergeView(store: store, source: project) { dismiss() } }
            } else {
                ContentUnavailableView("Project Merged", systemImage: "folder")
            }
        }
    }
}

struct ProjectEditor: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Project
    private let isNew: Bool

    init(store: AppStore, project: Project?) {
        self.store = store
        isNew = project == nil
        let settings = store.state.settings
        _draft = State(initialValue: project ?? Project(name: "", focusMinutes: settings.defaultFocusMinutes,
            shortBreakMinutes: settings.defaultShortBreakMinutes, longBreakMinutes: settings.defaultLongBreakMinutes))
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Details") {
                        TextField("Project name", text: $draft.name).accessibilityIdentifier("project.name")
                        Picker("Status", selection: $draft.status) {
                            ForEach(ProjectStatus.allCases) { Text($0.title).tag($0) }
                        }.disabled(store.state.activeTimer?.projectID == draft.id)
                    }
                    Section {
                        MinutePicker(title: "Focus", value: $draft.focusMinutes, range: 10...60)
                        MinutePicker(title: "Short break", value: $draft.shortBreakMinutes, range: 1...60)
                        MinutePicker(title: "Long break", value: $draft.longBreakMinutes, range: 1...60)
                    } header: { Text("Default durations") } footer: {
                        Text("Changing the focus default replaces this project's remembered session duration.")
                    }
                    if store.state.activeTimer?.projectID == draft.id {
                        Text("End this project's timer to change its status. Duration changes apply to future sessions.")
                            .foregroundStyle(.secondary)
                    }
                }.listRowBackground(AppTheme.surface)
            }
            .appScreen()
            .navigationTitle(isNew ? "New Project" : "Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if store.saveProject(draft) { dismiss() }
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.name.count > 100)
                    .accessibilityIdentifier("project.save")
                }
            }
        }
    }
}

struct MergeView: View {
    @Bindable var store: AppStore
    let source: Project
    let onMerged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var destination: UUID?
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("Merge \(source.name) into") {
                        Picker("Destination", selection: $destination) {
                            Text("Choose a project").tag(Optional<UUID>.none)
                            ForEach(store.state.projects.filter { $0.id != source.id && $0.id != store.state.activeTimer?.projectID }) {
                                Text($0.name).tag(Optional($0.id))
                            }
                        }
                        Text("All session history will move. The destination keeps its status and duration settings.")
                            .foregroundStyle(.secondary)
                        Button("Merge Projects", role: .destructive) { confirming = true }.disabled(destination == nil)
                    }
                }.listRowBackground(AppTheme.surface)
            }
            .appScreen()
            .navigationTitle("Merge Project").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog("Merge \(source.name) into \(destination.map { store.projectName($0) } ?? "project")?",
                isPresented: $confirming, titleVisibility: .visible) {
                Button("Merge and Remove \(source.name)", role: .destructive) {
                    if let destination, store.update({ try TimerEngine.merge(&$0, source: source.id, destination: destination) }) {
                        dismiss()
                        onMerged()
                    }
                }
            } message: { Text("This cannot be undone. Export a backup first if you may want to restore the original projects.") }
        }
    }
}

struct MinutePicker: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var body: some View {
        Picker(title, selection: $value) {
            ForEach(range, id: \.self) { Text("\($0) min").tag($0) }
        }
    }
}
