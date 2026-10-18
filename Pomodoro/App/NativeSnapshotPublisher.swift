#if NATIVE_INTEGRATIONS
import Foundation
import WidgetKit

@MainActor struct NativeSnapshotPublisher: SnapshotPublishing {
    func publish(_ state: AppSnapshot, now: Date) throws {
        guard let directory = SharedWidgetContainer.directory() else {
            throw AppError.invalid("Widget storage is unavailable for this installation.")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = Statistics.today(now, calendar: calendar)
        let summary = WidgetSnapshot.SavedFocus(dayStart: day.start, dayEnd: day.end,
            timeZoneIdentifier: calendar.timeZone.identifier,
            seconds: Statistics.total(state, interval: day, now: now))
        let projectSummaries = state.projects.filter { $0.status == .ongoing }.map { project in
            WidgetSnapshot.ProjectDaySummary(
                projectID: project.id,
                savedFocus: WidgetSnapshot.SavedFocus(dayStart: day.start, dayEnd: day.end,
                    timeZoneIdentifier: calendar.timeZone.identifier,
                    seconds: Statistics.total(state, projectID: project.id, interval: day, now: now)),
                targetMinutes: GoalEngine.dailyTarget(projectID: project.id, on: now, plan: state.goalPlan, calendar: calendar))
        }
        let snapshot = WidgetSnapshot(state: state, now: now, savedFocus: summary,
                                      projectDaySummaries: projectSummaries)
        if let existing = WidgetSnapshotFile.read(in: directory), snapshot.hasSameDisplayContent(as: existing) { return }
        try WidgetSnapshotFile.write(snapshot, in: directory)
        WidgetCenter.shared.reloadTimelines(ofKind: "PomodoroFocus")
    }
}
#endif
