import SwiftUI

struct ConsistencyDetailsView: View {
    @Bindable var store: AppStore
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let current = Statistics.consistency(store.state, weekStart: now, now: now)
            let days = Statistics.dailySummaries(store.state, interval: current.week, now: now)
            List {
                Section("This week · All projects") {
                    Text("\(current.focusedDays) of \(current.targetDays) focused days")
                        .font(.title2.bold())
                    HStack(spacing: 0) {
                        ForEach(days) { day in
                            VStack(spacing: 7) {
                                Image(systemName: day.focusSeconds >= 600 ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(day.focusSeconds >= 600 ? Color.indigo : Color.secondary)
                                    .accessibilityHidden(true)
                                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted))
                            .accessibilityValue(day.focusSeconds >= 600 ? "Focused" : "Not focused")
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("consistency.week")
                }
                Section {
                    Picker("Focused days per week", selection: Binding(
                        get: { store.state.settings.consistencyTargetDays },
                        set: { value in _ = store.update { $0.settings.consistencyTargetDays = value } }
                    )) {
                        ForEach(1...7, id: \.self) { Text("\($0) days").tag($0) }
                    }
                    .accessibilityIdentifier("consistency.target")
                }
                Section("Previous weeks") {
                    ForEach(1...8, id: \.self) { offset in
                        let date = GoalEngine.calendar().date(byAdding: .day, value: -7 * offset, to: current.week.start)!
                        let summary = Statistics.consistency(store.state, weekStart: date, now: now)
                        LabeledContent(summary.week.start.formatted(date: .abbreviated, time: .omitted),
                                       value: "\(summary.focusedDays) days")
                    }
                }
                Section {
                    Text("A day counts when you save at least 10 minutes of focus. All projects contribute; break time does not count.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(AppTheme.surface)
            .appScreen()
        }
        .navigationTitle("Consistency")
    }
}
