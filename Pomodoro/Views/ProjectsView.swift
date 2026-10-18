import SwiftUI

struct ProjectsView: View {
    @Bindable var store: AppStore
    @Bindable var navigation: AppNavigation
    @State private var showingOnHold = false
    @State private var showingCompleted = false

    var body: some View {
        List {
            LegacyDailyGoalAssignmentSection(store: store)
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
                            let count = SessionPlanText.items(from: project.breadcrumb?.text).count
                            Button(count == 0 ? "Plan next session" : "Session plan · \(count) \(count == 1 ? "task" : "tasks")",
                                   systemImage: "arrow.turn.down.right") {
                                navigation.requestNextSessionPlan(projectID: project.id)
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
                            Button("Project settings", systemImage: "slider.horizontal.3") { editing = true }
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
                .sheet(isPresented: $merging) { MergeView(store: store, source: project) { dismiss() } }
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
    @State private var draft: ProjectSettingsDraft
    @State private var path: [ProjectSettingsPage]
    @State private var confirmingDiscard = false
    @State private var error: String?
    private let isNew: Bool
    private let unavailable: Bool

    init(store: AppStore, project: Project?, createNew: Bool = false, initialPage: ProjectSettingsPage? = nil) {
        self.store = store
        isNew = createNew
        let existing = store.makeProjectSettingsDraft(projectID: project?.id)
        unavailable = !createNew && existing == nil
        _draft = State(initialValue: existing ?? store.makeProjectSettingsDraft(projectID: nil)!)
        _path = State(initialValue: initialPage.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if unavailable {
                    ContentUnavailableView("Project unavailable", systemImage: "folder",
                        description: Text("Return to Projects and open the project again."))
                } else {
                    Form {
                        Section {
                            TextField("Name", text: $draft.name).accessibilityIdentifier("project.name")
                            if !isNew {
                                Picker("Status", selection: $draft.status) {
                                    ForEach(ProjectStatus.allCases) { Text($0.title).tag($0) }
                                }
                                .disabled(store.state.activeTimer?.projectID == draft.projectID)
                            }
                        }
                        if isNew {
                            Section {
                                DisclosureGroup("Timer settings") { timerRows }
                            }
                        } else {
                            Section("Timers") { timerRows }
                        }
                        if !isNew {
                            Section("Goals") {
                                NavigationLink(value: ProjectSettingsPage.daily) {
                                    LabeledContent("Daily goal", value: dailySummary)
                                }
                                NavigationLink(value: ProjectSettingsPage.weekly) {
                                    LabeledContent("Weekly goal", value: draft.weeklyMinutes.map(goalLabel) ?? "Off")
                                }
                            }
                        }
                        if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
                    }
                }
            }
            .appScreen()
            .navigationTitle(unavailable ? "Project settings" : isNew ? "New project" : "Project settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !unavailable {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).count > 100
                                      || !draft.hasChanges)
                            .accessibilityIdentifier("project.save")
                    }
                }
            }
            .navigationDestination(for: ProjectSettingsPage.self) { page in
                switch page {
                case .daily: DailyGoalsDraftView(draft: $draft)
                case .dailyTarget(let title, let indices):
                    GoalMinutesEditor(title: title, minutes: dailyBinding(indices), maximum: 1440, allowsRest: true)
                case .weekly: WeeklyGoalsDraftView(draft: $draft)
                case .weeklyTarget:
                    GoalMinutesEditor(title: "Weekly goal", minutes: weeklyBinding, maximum: 10080, allowsRest: false)
                case .scheduledWeekly(let day):
                    ScheduledWeeklyGoalDraftView(draft: $draft, day: day)
                }
            }
            .interactiveDismissDisabled(draft.hasChanges && !unavailable)
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            } message: { Text("Your project settings have not been saved.") }
            .alert("Unable to save project settings", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
        .onAppear {
            if !isNew && store.state.projects.contains(where: { $0.id == draft.projectID }) == false {
                error = "This project is no longer available. Return to Projects and open it again."
            }
        }
    }

    private var dailySummary: String {
        guard let schedule = draft.dailySchedule else { return "Not set" }
        if schedule.allSatisfy({ $0 == schedule[0] }) { return "\(goalLabel(schedule[0])) daily" }
        if schedule.prefix(5).allSatisfy({ $0 == schedule[0] }) && schedule.suffix(2).allSatisfy({ $0 == schedule[5] }) {
            return schedule[5] == 0 ? "\(goalLabel(schedule[0])) weekdays" : "Weekdays & weekends"
        }
        return "Custom schedule"
    }

    @ViewBuilder private var timerRows: some View {
        timerRow("Focus", value: $draft.focusMinutes, range: 10...60)
        timerRow("Short break", value: $draft.shortBreakMinutes, range: 1...60)
        timerRow("Long break", value: $draft.longBreakMinutes, range: 1...60)
    }

    private var weeklyBinding: Binding<Int> {
        Binding(get: { draft.weeklyMinutes ?? 60 }, set: { draft.weeklyMinutes = $0 })
    }

    private func dailyBinding(_ indices: [Int]) -> Binding<Int> {
        Binding(get: { indices.first.flatMap { draft.dailySchedule?[$0] } ?? 0 }, set: { value in
            var schedule = draft.dailySchedule ?? Array(repeating: 0, count: 7)
            for index in indices { schedule[index] = value }
            draft.dailySchedule = schedule
        })
    }

    private func timerRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        MinutePicker(title: title, value: value, range: range)
    }

    private func save() {
        guard store.saveProjectSettings(draft) else {
            error = store.errorMessage ?? "The settings could not be saved."
            store.errorMessage = nil
            return
        }
        if isNew {
            navigation.selectedProjectID = draft.projectID
            navigation.showFocus()
        }
        dismiss()
    }

    private func cancel() {
        if draft.hasChanges { confirmingDiscard = true }
        else { dismiss() }
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
