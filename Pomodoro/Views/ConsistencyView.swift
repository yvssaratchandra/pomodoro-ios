import SwiftUI

struct ConsistencyDetailsView: View {
    let state: AppSnapshot
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let current = Statistics.consistency(state, weekStart: now, now: now)
            List {
                Section("This Week · All Projects") {
                    Text("\(current.focusedDays) of \(current.targetDays) focused days")
                        .font(.title2.bold())
                    if current.isProvisional {
                        Text("Today includes a running session")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Previous Weeks") {
                    ForEach(1...8, id: \.self) { offset in
                        let date = GoalEngine.calendar().date(byAdding: .day, value: -7 * offset, to: current.week.start)!
                        let summary = Statistics.consistency(state, weekStart: date, now: now)
                        LabeledContent(summary.week.start.formatted(date: .abbreviated, time: .omitted),
                                       value: "\(summary.focusedDays) days")
                    }
                }
                Section {
                    Text("A day counts when you focus for at least 10 minutes. All projects contribute; break time does not count.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(AppTheme.surface)
            .appScreen()
        }
        .navigationTitle("Consistency")
    }
}
