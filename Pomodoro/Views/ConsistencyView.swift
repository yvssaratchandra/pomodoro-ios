import SwiftUI

struct ConsistencyView: View {
    let state: AppSnapshot
    let now: Date
    var body: some View {
        let current = Statistics.consistency(state, weekStart: now, now: now)
        VStack(alignment: .leading, spacing: 8) {
            Text("Focused on \(current.focusedDays) of \(current.targetDays) days this week").font(.headline)
            Text("10 minutes of actual focus qualifies a day.").font(.caption).foregroundStyle(.secondary)
            if current.isProvisional { Text("Includes current session · provisional").font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Previous 8 weeks") {
                ForEach(1...8, id: \.self) { offset in
                    let date = GoalEngine.calendar().date(byAdding: .day, value: -7 * offset, to: current.week.start)!
                    let summary = Statistics.consistency(state, weekStart: date, now: now)
                    LabeledContent(summary.week.start.formatted(date: .abbreviated, time: .omitted), value: "\(summary.focusedDays) focused days")
                }
            }
        }
    }
}
