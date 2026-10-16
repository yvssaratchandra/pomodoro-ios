import SwiftUI

struct DailyGoalsEditor: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: [Int]
    @State private var error: String?
    private let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    init(store: AppStore) {
        self.store = store
        let day = LocalDay(Date(), calendar: GoalEngine.calendar())
        _draft = State(initialValue: store.state.goalPlan.dailyRevisions.filter { $0.effectiveFrom <= day }.max(by: { $0.effectiveFrom < $1.effectiveFrom })?.minutes ?? Array(repeating: 240, count: 7))
    }
    var body: some View {
        Form {
            Section {
                ForEach(0..<7) { index in
                    VStack(alignment: .leading) {
                        Text(days[index]).font(.headline)
                        HStack {
                            Picker("Hours", selection: value(index, hours: true)) { ForEach(0...24, id: \.self) { Text("\($0) hr").tag($0) } }
                            Picker("Minutes", selection: value(index, hours: false)) { ForEach(0...59, id: \.self) { Text("\($0) min").tag($0) } }
                                .disabled(draft[index] == 1440)
                        }
                        if draft[index] == 0 { Text("Rest day").foregroundStyle(.secondary) }
                    }
                }
                Button("Same every day") { draft = Array(repeating: draft[0], count: 7) }
            } footer: { Text("Same every day copies Monday. Zero means rest day. Changes apply from today; earlier targets stay unchanged.") }
        }
        .appScreen().navigationTitle("Daily goals")
        .toolbar { Button("Save") {
            if store.saveDailyGoals(draft) { dismiss() }
            else { error = store.errorMessage; store.errorMessage = nil }
        } }
        .alert("Unable to save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func value(_ index: Int, hours: Bool) -> Binding<Int> {
        Binding(get: { hours ? draft[index] / 60 : draft[index] % 60 }, set: {
            draft[index] = min(1440, hours ? $0 * 60 + draft[index] % 60 : draft[index] / 60 * 60 + $0)
        })
    }
}

struct WeeklyGoalEditor: View {
    let store: AppStore
    let projectID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: Bool
    @State private var minutes: Int
    @State private var error: String?
    init(store: AppStore, projectID: UUID) {
        self.store = store; self.projectID = projectID
        let effective = GoalEngine.weeklyEffectiveDate(projectID: projectID, plan: store.state.goalPlan, now: Date())
        let target = GoalEngine.weeklyTarget(projectID: projectID, weekStart: effective, plan: store.state.goalPlan)
        _enabled = State(initialValue: target != nil); _minutes = State(initialValue: target ?? 60)
    }
    var body: some View {
        Form {
            Toggle("Weekly target", isOn: $enabled)
            if enabled {
                Picker("Hours", selection: Binding(get: { minutes / 60 }, set: { minutes = max(1, min(10080, $0 * 60 + minutes % 60)) })) {
                    ForEach(0...168, id: \.self) { Text("\($0) hr").tag($0) }
                }
                Picker("Minutes", selection: Binding(get: { minutes % 60 }, set: { minutes = max(1, min(10080, minutes / 60 * 60 + $0)) })) {
                    ForEach(0...59, id: \.self) { Text("\($0) min").tag($0) }
                }.disabled(minutes == 10080)
            }
            Text("Effective \(GoalEngine.weeklyEffectiveDate(projectID: projectID, plan: store.state.goalPlan, now: Date()).formatted(date: .abbreviated, time: .omitted)). Subsequent changes start next Monday.").foregroundStyle(.secondary)
        }.appScreen().navigationTitle("Project weekly goal")
        .toolbar { Button("Save") {
            if store.saveWeeklyGoal(projectID: projectID, minutes: enabled ? minutes : nil) { dismiss() }
            else { error = store.errorMessage; store.errorMessage = nil }
        } }
        .alert("Unable to save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}
