import SwiftUI

struct GoalsView: View {
    @Bindable var store: AppStore
    @State private var replacementProjectID: UUID?
    @State private var showReplacementConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var error: String?

    var body: some View {
        List {
            if let legacy = store.state.goalPlan.pendingLegacyDailySchedule {
                Section("Previous daily goal") {
                    Text(legacySummary(legacy)).foregroundStyle(.secondary)
                    ForEach(store.state.projects) { project in
                        let hasGoal = GoalEngine.dailySchedule(projectID: project.id, on: Date(), plan: store.state.goalPlan) != nil
                        Button(hasGoal ? "Replace for \(project.name)" : "Assign to \(project.name)") {
                            if hasGoal {
                                replacementProjectID = project.id
                                showReplacementConfirmation = true
                            } else {
                                assign(to: project.id, replacing: false)
                            }
                        }
                    }
                    Button("Discard previous goal", role: .destructive) { showDiscardConfirmation = true }
                }
            }
            Section("Projects") {
                if store.state.projects.isEmpty {
                    ContentUnavailableView("No projects", systemImage: "folder",
                        description: Text("Create a project to set its goals."))
                } else {
                    ForEach(store.state.projects) { project in
                        NavigationLink {
                            ProjectGoalsEditor(store: store, projectID: project.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name)
                                Text(projectDailySummary(project.id)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("More goals") {
                NavigationLink("Consistency") { ConsistencyDetailsView(store: store) }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Goals")
        .confirmationDialog("Replace this project's daily goal?", isPresented: $showReplacementConfirmation) {
            Button("Replace daily goal", role: .destructive) {
                if let replacementProjectID { assign(to: replacementProjectID, replacing: true) }
            }
            Button("Cancel", role: .cancel) { replacementProjectID = nil }
        }
        .confirmationDialog("Discard previous daily goal?", isPresented: $showDiscardConfirmation) {
            Button("Discard previous goal", role: .destructive) {
                if !store.discardLegacyDailyGoal() { error = store.errorMessage; store.errorMessage = nil }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Unable to update goal", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func assign(to id: UUID, replacing: Bool) {
        if !store.assignLegacyDailyGoal(to: id, replacingExisting: replacing) {
            error = store.errorMessage
            store.errorMessage = nil
        }
    }

    private func projectDailySummary(_ id: UUID) -> String {
        guard let values = GoalEngine.dailySchedule(projectID: id, on: Date(), plan: store.state.goalPlan) else { return "No daily goal" }
        if values.allSatisfy({ $0 == values[0] }) { return "Every day · \(goalLabel(values[0]))" }
        if values.prefix(5).allSatisfy({ $0 == values[0] }) && values.suffix(2).allSatisfy({ $0 == values[5] }) {
            return "Weekdays · \(goalLabel(values[0])) / Weekend · \(goalLabel(values[5]))"
        }
        return "Custom schedule"
    }

    private func legacySummary(_ values: [Int]) -> String {
        guard values.count == 7 else { return "Previous daily schedule" }
        if values.allSatisfy({ $0 == values[0] }) { return "Every day · \(goalLabel(values[0]))" }
        if values.prefix(5).allSatisfy({ $0 == values[0] }) && values.suffix(2).allSatisfy({ $0 == values[5] }) {
            return "Weekdays · \(goalLabel(values[0])) / Weekend · \(goalLabel(values[5]))"
        }
        return "Custom schedule · choose a project to assign"
    }
}

private struct ProjectGoalsEditor: View {
    let store: AppStore
    let projectID: UUID
    private var projectName: String { store.projectName(projectID) }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    DailyGoalsEditor(store: store, projectID: projectID)
                } label: {
                    LabeledContent("Daily schedule", value: dailyValue)
                }
                NavigationLink {
                    WeeklyGoalEditor(store: store, projectID: projectID)
                } label: {
                    LabeledContent("Weekly target", value: weeklyValue)
                }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle(projectName)
    }

    private var dailyValue: String {
        guard let value = GoalEngine.dailyTarget(projectID: projectID, on: Date(), plan: store.state.goalPlan) else { return "Off" }
        return goalLabel(value)
    }
    private var weeklyValue: String {
        guard let value = GoalEngine.weeklyTarget(projectID: projectID, weekStart: Date(), plan: store.state.goalPlan) else { return "Off" }
        return goalLabel(value)
    }
}

private enum DailyMode: String, CaseIterable, Identifiable {
    case everyDay = "Every Day", split = "Weekdays / Weekend", custom = "Custom"
    var id: String { rawValue }
}

struct DailyGoalsEditor: View {
    let store: AppStore
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var reviewing = false
    @State private var mode: DailyMode
    @State private var everyDay: Int
    @State private var weekdays: Int
    @State private var weekend: Int
    @State private var custom: [Int]
    @State private var error: String?
    private let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    init(store: AppStore, projectID: UUID) {
        self.store = store
        self.projectID = projectID
        let day = LocalDay(Date(), calendar: GoalEngine.calendar())
        let values = GoalEngine.dailySchedule(projectID: projectID, on: day.date(calendar: GoalEngine.calendar())!, plan: store.state.goalPlan)
            ?? Array(repeating: 0, count: 7)
        let detected: DailyMode = values.allSatisfy { $0 == values[0] } ? .everyDay :
            (values.prefix(5).allSatisfy { $0 == values[0] } && values.suffix(2).allSatisfy { $0 == values[5] } ? .split : .custom)
        _mode = State(initialValue: detected)
        _everyDay = State(initialValue: values[0])
        _weekdays = State(initialValue: values[0])
        _weekend = State(initialValue: values[5])
        _custom = State(initialValue: values)
    }
    private var draft: [Int] {
        switch mode {
        case .everyDay: Array(repeating: everyDay, count: 7)
        case .split: Array(repeating: weekdays, count: 5) + Array(repeating: weekend, count: 2)
        case .custom: custom
        }
    }
    var body: some View {
        Form {
            Section {
                Picker("Schedule", selection: $mode) {
                    ForEach(DailyMode.allCases) { Text($0.rawValue).tag($0) }
                }
            } footer: { Text("Changes apply from today. Earlier goals remain as recorded.") }
            Section("Targets") {
                switch mode {
                case .everyDay:
                    NavigationLink { GoalMinutesEditor(title: "Every Day", minutes: $everyDay, maximum: 1440, allowsRest: true) } label: {
                        LabeledContent("Every Day", value: goalLabel(everyDay))
                    }
                case .split:
                    NavigationLink { GoalMinutesEditor(title: "Weekdays", minutes: $weekdays, maximum: 1440, allowsRest: true) } label: {
                        LabeledContent("Weekdays", value: goalLabel(weekdays))
                    }
                    NavigationLink { GoalMinutesEditor(title: "Weekend", minutes: $weekend, maximum: 1440, allowsRest: true) } label: {
                        LabeledContent("Weekend", value: goalLabel(weekend))
                    }
                case .custom:
                    ForEach(0..<7) { index in
                        NavigationLink {
                            GoalMinutesEditor(title: days[index], minutes: Binding(
                                get: { custom[index] }, set: { custom[index] = $0 }
                            ), maximum: 1440, allowsRest: true)
                        } label: {
                            LabeledContent(days[index], value: goalLabel(custom[index]))
                        }
                    }
                }
            }
            DisclosureGroup("Review week", isExpanded: $reviewing) {
                ForEach(0..<7) { index in
                    LabeledContent(days[index], value: goalLabel(draft[index]))
                }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen().navigationTitle("Daily goals")
        .onChange(of: mode) { _, _ in reviewing = true }
        .toolbar {
            Button("Save") {
                if store.saveDailyGoals(projectID: projectID, minutes: draft) { dismiss() }
                else { error = store.errorMessage; store.errorMessage = nil }
            }
        }
        .alert("Unable to save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

private func goalLabel(_ minutes: Int) -> String {
    minutes == 0 ? "Rest day" : DurationText.work(Double(minutes * 60))
}

private struct GoalMinutesEditor: View {
    let title: String
    @Binding var minutes: Int
    let maximum: Int
    let allowsRest: Bool
    var body: some View {
        Form {
            if allowsRest {
                Toggle("Rest day", isOn: Binding(
                    get: { minutes == 0 }, set: { minutes = $0 ? 0 : 60 }
                ))
            }
            if minutes > 0 || !allowsRest {
                Picker("Hours", selection: Binding(
                    get: { minutes / 60 }, set: { minutes = min(maximum, max(allowsRest ? 0 : 1, $0 * 60 + minutes % 60)) }
                )) {
                    ForEach(0...(maximum / 60), id: \.self) { Text("\($0) hr").tag($0) }
                }
                Picker("Minutes", selection: Binding(
                    get: { minutes % 60 }, set: { minutes = min(maximum, max(allowsRest ? 0 : 1, minutes / 60 * 60 + $0)) }
                )) {
                    ForEach(0...59, id: \.self) { Text("\($0) min").tag($0) }
                }.disabled(minutes == maximum)
            }
        }.appScreen().navigationTitle(title)
    }
}

struct WeeklyGoalEditor: View {
    let store: AppStore
    let projectID: UUID
    let effectiveWeek: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var minutes: Int
    @State private var error: String?
    @State private var pendingCancellation: Date?

    init(store: AppStore, projectID: UUID, effectiveWeek: Date? = nil) {
        self.store = store
        self.projectID = projectID
        self.effectiveWeek = effectiveWeek
        let week = effectiveWeek ?? GoalEngine.week(containing: Date()).start
        let target = GoalEngine.weeklyTarget(projectID: projectID, weekStart: week, plan: store.state.goalPlan)
        _enabled = State(initialValue: target != nil)
        _minutes = State(initialValue: target ?? 60)
    }
    private var futureRevisions: [ProjectWeeklyGoalRevision] {
        let today = LocalDay(GoalEngine.week(containing: Date()).start, calendar: GoalEngine.calendar())
        return store.state.goalPlan.weeklyProjectRevisions
            .filter { $0.projectID == projectID && $0.effectiveFrom > today }
            .sorted { $0.effectiveFrom < $1.effectiveFrom }
    }
    var body: some View {
        Form {
            Section {
                Toggle("Weekly target", isOn: $enabled)
                if enabled {
                    NavigationLink {
                        GoalMinutesEditor(title: "Weekly Target", minutes: $minutes,
                                          maximum: 10080, allowsRest: false)
                    } label: {
                        LabeledContent("Target", value: goalLabel(minutes))
                    }
                }
            } footer: {
                Text(effectiveWeek == nil ? "Changes this week's target. Earlier weeks stay the same." : "Changes the selected scheduled target.")
            }
            if effectiveWeek == nil && !futureRevisions.isEmpty {
                Section("Scheduled changes") {
                    ForEach(futureRevisions, id: \.effectiveFrom) { revision in
                        if let date = revision.effectiveFrom.date(calendar: GoalEngine.calendar()) {
                            NavigationLink {
                                WeeklyGoalEditor(store: store, projectID: projectID, effectiveWeek: date)
                            } label: {
                                LabeledContent("From \(date.formatted(date: .abbreviated, time: .omitted))",
                                               value: revision.minutes.map(goalLabel) ?? "Off")
                            }
                            .swipeActions {
                                Button("Cancel change", role: .destructive) { pendingCancellation = date }
                            }
                        }
                    }
                }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen().navigationTitle(effectiveWeek == nil ? "Weekly Goal" : "Scheduled Goal")
        .toolbar {
            Button("Save") {
                if store.saveWeeklyGoal(projectID: projectID, minutes: enabled ? minutes : nil, effectiveWeek: effectiveWeek) { dismiss() }
                else { error = store.errorMessage; store.errorMessage = nil }
            }
        }
        .confirmationDialog("Cancel scheduled change?", isPresented: Binding(
            get: { pendingCancellation != nil }, set: { if !$0 { pendingCancellation = nil } }
        )) {
            Button("Cancel Change", role: .destructive) {
                if let date = pendingCancellation,
                   !store.cancelScheduledWeeklyGoal(projectID: projectID, effectiveWeek: date) {
                    error = store.errorMessage ?? "The scheduled change could not be cancelled."
                    store.errorMessage = nil
                }
                pendingCancellation = nil
            }
        }
        .alert("Unable to save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
