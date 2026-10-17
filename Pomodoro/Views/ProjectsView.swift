import SwiftUI

struct ProjectsView: View {
    @Bindable var store: AppStore
    @Bindable var navigation: AppNavigation
    @State private var showingOnHold = false
    @State private var showingCompleted = false

    var body: some View {
        List {
            if store.state.projects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "folder")
                } description: {
                    Text("Create a project to begin focusing.")
                } actions: {
                    Button("Create Project") { navigation.showingProjectCreation = true }
                }
            }
            let active = store.state.projects.filter { $0.status == .ongoing }
            if !active.isEmpty {
                Section("Active") {
                    ForEach(active) { project in projectRow(project) }
                }
            }
            let onHold = store.state.projects.filter { $0.status == .suspended }
            if !onHold.isEmpty {
                DisclosureGroup("On Hold (\(onHold.count))", isExpanded: $showingOnHold) {
                    ForEach(onHold) { project in projectRow(project) }
                }
            }
            let completed = store.state.projects.filter { $0.status == .completed }
            if !completed.isEmpty {
                DisclosureGroup("Completed (\(completed.count))", isExpanded: $showingCompleted) {
                    ForEach(completed) { project in projectRow(project) }
                }
            }
        }
        .appScreen()
        .navigationTitle("Projects")
        .toolbar { Button("New Project", systemImage: "plus") { navigation.showingProjectCreation = true }.accessibilityIdentifier("projects.new") }
    }

    private func projectRow(_ project: Project) -> some View {
        NavigationLink {
            ProjectDetail(store: store, projectID: project.id)
        } label: {
            Label(project.name, systemImage: "folder")
                .lineLimit(1)
                .frame(minHeight: 36, alignment: .leading)
        }
        .listRowBackground(AppTheme.surface)
    }
}

struct ProjectDetail: View {
    @Bindable var store: AppStore
    let projectID: UUID
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var merging = false
    @State private var editingNextStep = false
    @State private var showingGoal = false
    @State private var showingShortcut = false
    @State private var confirmingDeletion = false
    @State private var error: String?
    private var project: Project? { store.state.projects.first { $0.id == projectID } }
    private var sessions: [FocusSession] {
        store.state.sessions.filter { $0.projectID == projectID }.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        Group {
            if let project {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    let now = timeline.date
                    List {
                        Section {
                            if project.status != .ongoing { LabeledContent("Status", value: project.status.title) }
                            LabeledContent("Total focus", value: DurationText.summary(Statistics.total(store.state, projectID: project.id, now: now)))
                            if let target = GoalEngine.weeklyTarget(projectID: project.id, weekStart: now, plan: store.state.goalPlan) {
                                LabeledContent("This week", value: "\(DurationText.summary(Statistics.total(store.state, projectID: project.id, interval: GoalEngine.week(containing: now), now: now))) / \(DurationText.summary(Double(target * 60)))")
                            }
                            LabeledContent("Focus duration", value: "\(project.preferredFocusMinutes) min")
                        }
                        Section {
                            if project.breadcrumb != nil {
                                BreadcrumbCard(store: store, project: project)
                            } else {
                                Button("Plan next session", systemImage: "arrow.turn.down.right") { editingNextStep = true }
                            }
                            Button("Thoughts", systemImage: "text.bubble") { navigation.showThoughts(projectID: project.id) }
                        }
                        Section("Recent sessions") {
                            if sessions.isEmpty { Text("No sessions yet").foregroundStyle(.secondary) }
                            ForEach(sessions.prefix(5)) { session in
                                NavigationLink { SessionDetailView(store: store, sessionID: session.id) } label: {
                                    SessionRow(session: session, name: project.name, hideProject: true)
                                }
                                .swipeActions { Button("Delete", role: .destructive) { _ = store.deleteSession(session.id) } }
                            }
                            if sessions.count > 5 {
                                NavigationLink("View all sessions") { ProjectSessionHistory(store: store, projectID: project.id) }
                            }
                        }
                    }
                }
                .appScreen()
                .navigationTitle(project.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit Project", systemImage: "pencil") { editing = true }
                            Button("Weekly Goal", systemImage: "target") { showingGoal = true }
                            if project.status == .ongoing {
                                Button("Create Shortcut", systemImage: "square.and.arrow.up") { showingShortcut = true }
                                    .accessibilityIdentifier("project.quickstart")
                            }
                            Button("Merge Project", systemImage: "arrow.triangle.merge") { merging = true }
                                .disabled(store.state.projects.count < 2 || store.state.activeTimer?.projectID == project.id)
                            if store.canDeleteProject(id: project.id) {
                                Button(role: .destructive) { confirmingDeletion = true } label: {
                                    Label("Delete Empty Project", systemImage: "trash")
                                }
                            }
                        } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More project actions") }
                    }
                }
                .sheet(isPresented: $editing) { ProjectEditor(store: store, project: project) }
                .sheet(isPresented: $editingNextStep) { BreadcrumbEditor(store: store, projectID: project.id) }
                .sheet(isPresented: $merging) { MergeView(store: store, source: project) { dismiss() } }
                .navigationDestination(isPresented: $showingGoal) { WeeklyGoalEditor(store: store, projectID: project.id) }
                .navigationDestination(isPresented: $showingShortcut) { QuickStartSetupView(store: store, projectID: project.id) }
                .confirmationDialog("Delete \(project.name)?", isPresented: $confirmingDeletion) {
                    Button("Delete Project", role: .destructive) {
                        if store.deleteEmptyProject(id: project.id) { dismiss() }
                        else { error = store.errorMessage; store.errorMessage = nil }
                    }
                } message: { Text("Only an empty project can be deleted.") }
                .alert("Unable to Delete Project", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
            } else {
                ContentUnavailableView("Project Unavailable", systemImage: "folder")
            }
        }
    }
}

private struct ProjectSessionHistory: View {
    @Bindable var store: AppStore
    let projectID: UUID

    var body: some View {
        List {
            ForEach(store.state.sessions.filter { $0.projectID == projectID }.sorted { $0.startedAt > $1.startedAt }) { session in
                NavigationLink { SessionDetailView(store: store, sessionID: session.id) } label: {
                    SessionRow(session: session, name: store.projectName(projectID), hideProject: true)
                }
                .swipeActions { Button("Delete", role: .destructive) { _ = store.deleteSession(session.id) } }
            }
        }
        .appScreen()
        .navigationTitle("Sessions")
    }
}

struct ProjectEditor: View {
    @Bindable var store: AppStore
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Project
    @State private var focusDuration: Int
    private let originalFocusDuration: Int
    @State private var showingTimerSettings = false
    @State private var error: String?
    private let isNew: Bool

    init(store: AppStore, project: Project?) {
        self.store = store
        isNew = project == nil
        let settings = store.state.settings
        let starting = project ?? Project(name: "", focusMinutes: settings.defaultFocusMinutes,
            shortBreakMinutes: settings.defaultShortBreakMinutes, longBreakMinutes: settings.defaultLongBreakMinutes)
        originalFocusDuration = starting.preferredFocusMinutes
        _focusDuration = State(initialValue: starting.preferredFocusMinutes)
        _draft = State(initialValue: starting)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Project Name", text: $draft.name).accessibilityIdentifier("project.name")
                    if !isNew {
                        Picker("Status", selection: $draft.status) {
                            ForEach(ProjectStatus.allCases) { Text($0.title).tag($0) }
                        }.disabled(store.state.activeTimer?.projectID == draft.id)
                    }
                }
                if isNew {
                    DisclosureGroup("Timer Settings", isExpanded: $showingTimerSettings) { timerSettings }
                } else {
                    Section("Timer Settings") { timerSettings }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .appScreen()
            .navigationTitle(isNew ? "New Project" : "Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if store.saveProject(draft, focusDuration: focusDuration == originalFocusDuration ? nil : focusDuration) {
                            if isNew {
                                navigation.selectedProjectID = draft.id
                                navigation.showFocus()
                            }
                            dismiss()
                        } else { error = store.errorMessage; store.errorMessage = nil }
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.name.count > 100)
                    .accessibilityIdentifier("project.save")
                }
            }
        }
    }

    private var timerSettings: some View {
        Group {
            MinutePicker(title: "Focus", value: $focusDuration, range: 10...60)
            MinutePicker(title: "Short Break", value: $draft.shortBreakMinutes, range: 1...60)
            MinutePicker(title: "Long Break", value: $draft.longBreakMinutes, range: 1...60)
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
