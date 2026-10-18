import SwiftUI

struct DailyGoalsDraftView: View {
    @Binding var draft: ProjectSettingsDraft
    @State private var mode: DailyMode
    @State private var reviewing = false
    private let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    init(draft: Binding<ProjectSettingsDraft>) {
        _draft = draft
        let values = draft.wrappedValue.dailySchedule
        let mode: DailyMode
        if let values, values.allSatisfy({ $0 == values[0] }) { mode = .everyDay }
        else if let values, values.prefix(5).allSatisfy({ $0 == values[0] }) && values.suffix(2).allSatisfy({ $0 == values[5] }) { mode = .split }
        else { mode = values == nil ? .everyDay : .custom }
        _mode = State(initialValue: mode)
    }

    private var values: [Int] { draft.dailySchedule ?? Array(repeating: 0, count: 7) }
    private var shownValues: [Int] {
        switch mode {
        case .everyDay: Array(repeating: values[0], count: 7)
        case .split: Array(repeating: values[0], count: 5) + Array(repeating: values[5], count: 2)
        case .custom: values
        }
    }
    var body: some View {
        Form {
            if draft.dailySchedule == nil {
                Section {
                    Button("Set daily goal") { draft.dailySchedule = Array(repeating: 60, count: 7) }
                } footer: {
                    Text("Choose a daily focus target for this project.")
                }
            } else {
                Section {
                    Picker("Schedule", selection: $mode) {
                        ForEach(DailyMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: { Text("Changes apply from today. Earlier goals remain as recorded.") }
                Section("Targets") {
                    switch mode {
                    case .everyDay:
                        target("Every day", index: 0)
                    case .split:
                        target("Weekdays", index: 0)
                        target("Weekend", index: 5)
                    case .custom:
                        ForEach(0..<7, id: \.self) { index in target(weekdays[index], index: index) }
                    }
                }
                DisclosureGroup("Review week", isExpanded: $reviewing) {
                    ForEach(0..<7, id: \.self) { index in
                        LabeledContent(weekdays[index], value: goalLabel(shownValues[index]))
                    }
                }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Daily goal")
        .onChange(of: mode) { _, newMode in
            guard draft.dailySchedule != nil else { return }
            switch newMode {
            case .everyDay: draft.dailySchedule = Array(repeating: values[0], count: 7)
            case .split: draft.dailySchedule = Array(repeating: values[0], count: 5) + Array(repeating: values[5], count: 2)
            case .custom: break
            }
        }
    }

    private func target(_ title: String, index: Int) -> some View {
        let indices: [Int]
        switch mode {
        case .everyDay: indices = Array(0..<7)
        case .split: indices = index == 0 ? Array(0..<5) : [5, 6]
        case .custom: indices = [index]
        }
        return NavigationLink(value: ProjectSettingsPage.dailyTarget(title: title, indices: indices)) {
            LabeledContent(title, value: goalLabel(shownValues[index]))
        }
    }
}

private enum DailyMode: Hashable, CaseIterable {
    case everyDay, split, custom
    var title: String {
        switch self { case .everyDay: "Every day"; case .split: "Weekdays / weekend"; case .custom: "Custom" }
    }
}

struct WeeklyGoalsDraftView: View {
    @Binding var draft: ProjectSettingsDraft
    @State private var pendingCancellation: LocalDay?

    private var enabled: Binding<Bool> {
        Binding(get: { draft.weeklyMinutes != nil }, set: { draft.weeklyMinutes = $0 ? (draft.weeklyMinutes ?? 60) : nil })
    }
    var body: some View {
        Form {
            Section {
                Toggle("Weekly goal", isOn: enabled)
                if draft.weeklyMinutes != nil {
                    NavigationLink(value: ProjectSettingsPage.weeklyTarget) {
                        LabeledContent("Target", value: goalLabel(draft.weeklyMinutes ?? 60))
                    }
                }
            } footer: { Text("Changes apply to this week. Earlier weeks stay the same.") }
            if !draft.scheduledWeeklyRevisions.isEmpty {
                Section("Scheduled changes") {
                    ForEach(draft.scheduledWeeklyRevisions, id: \.effectiveFrom) { revision in
                        NavigationLink(value: ProjectSettingsPage.scheduledWeekly(revision.effectiveFrom)) {
                            LabeledContent(scheduledLabel(revision.effectiveFrom),
                                           value: revision.minutes.map(goalLabel) ?? "Off")
                        }
                        .swipeActions {
                            Button("Cancel change", role: .destructive) { pendingCancellation = revision.effectiveFrom }
                        }
                    }
                }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Weekly goal")
        .confirmationDialog("Cancel scheduled change?", isPresented: Binding(
            get: { pendingCancellation != nil }, set: { if !$0 { pendingCancellation = nil } }
        )) {
            Button("Cancel change", role: .destructive) {
                if let day = pendingCancellation { draft.cancelScheduledWeeklyGoal(for: day) }
                pendingCancellation = nil
            }
        }
    }
}

struct ScheduledWeeklyGoalDraftView: View {
    @Binding var draft: ProjectSettingsDraft
    let day: LocalDay

    private var revision: ProjectWeeklyGoalRevision? { draft.scheduledWeeklyRevisions.first { $0.effectiveFrom == day } }
    private var enabled: Binding<Bool> {
        Binding(get: { revision?.minutes != nil }, set: { draft.setScheduledWeeklyGoal($0 ? (revision?.minutes ?? 60) : nil, for: day) })
    }
    private var minutes: Binding<Int> {
        Binding(get: { revision?.minutes ?? 60 }, set: { draft.setScheduledWeeklyGoal($0, for: day) })
    }

    var body: some View {
        Form {
            Toggle("Weekly goal", isOn: enabled)
            if revision?.minutes != nil {
                NavigationLink {
                    GoalMinutesEditor(title: "Weekly target", minutes: minutes, maximum: 10080, allowsRest: false)
                } label: {
                    LabeledContent("Target", value: goalLabel(minutes.wrappedValue))
                }
            }
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle("Scheduled goal")
    }
}

struct GoalMinutesEditor: View {
    let title: String
    @Binding var minutes: Int
    let maximum: Int
    let allowsRest: Bool

    var body: some View {
        Form {
            if allowsRest {
                Toggle("Rest day", isOn: Binding(get: { minutes == 0 }, set: { minutes = $0 ? 0 : 60 }))
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
        }
        .listRowBackground(AppTheme.surface)
        .appScreen()
        .navigationTitle(title)
    }
}

struct LegacyDailyGoalAssignmentSection: View {
    @Bindable var store: AppStore
    @State private var replacementProjectID: UUID?
    @State private var showReplacementConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var error: String?

    var body: some View {
        if let legacy = store.state.goalPlan.pendingLegacyDailySchedule {
            Section("Previous daily goal") {
                Text(summary(legacy)).foregroundStyle(.secondary)
                ForEach(store.state.projects) { project in
                    let hasGoal = GoalEngine.dailySchedule(projectID: project.id, on: Date(), plan: store.state.goalPlan) != nil
                    Button(hasGoal ? "Replace for \(project.name)" : "Assign to \(project.name)") {
                        if hasGoal { replacementProjectID = project.id; showReplacementConfirmation = true }
                        else { assign(project.id, replacing: false) }
                    }
                }
                Button("Discard previous goal", role: .destructive) { showDiscardConfirmation = true }
            }
            .confirmationDialog("Replace this project's daily goal?", isPresented: $showReplacementConfirmation) {
                Button("Replace daily goal", role: .destructive) {
                    if let replacementProjectID { assign(replacementProjectID, replacing: true) }
                }
                Button("Cancel", role: .cancel) { replacementProjectID = nil }
            }
            .confirmationDialog("Discard previous daily goal?", isPresented: $showDiscardConfirmation) {
                Button("Discard previous goal", role: .destructive) {
                    if !store.discardLegacyDailyGoal() { captureError() }
                }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Unable to update goal", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func assign(_ id: UUID, replacing: Bool) {
        if !store.assignLegacyDailyGoal(to: id, replacingExisting: replacing) { captureError() }
    }
    private func captureError() { error = store.errorMessage; store.errorMessage = nil }
    private func summary(_ values: [Int]) -> String {
        guard values.count == 7 else { return "Previous daily schedule" }
        if values.allSatisfy({ $0 == values[0] }) { return "Every day · \(goalLabel(values[0]))" }
        if values.prefix(5).allSatisfy({ $0 == values[0] }) && values.suffix(2).allSatisfy({ $0 == values[5] }) {
            return "Weekdays · \(goalLabel(values[0])) / Weekend · \(goalLabel(values[5]))"
        }
        return "Custom schedule · choose a project to assign"
    }
}

func goalLabel(_ minutes: Int) -> String {
    minutes == 0 ? "Rest day" : DurationText.work(Double(minutes * 60))
}

private func scheduledLabel(_ day: LocalDay) -> String {
    day.date(calendar: GoalEngine.calendar())?.formatted(date: .abbreviated, time: .omitted) ?? "Scheduled change"
}
