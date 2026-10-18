import Foundation

struct ProjectSettingsBaseline: Equatable {
    let name: String
    let status: ProjectStatus
    let focusMinutes: Int
    let shortBreakMinutes: Int
    let longBreakMinutes: Int
    let dailySchedule: [Int]?
    let weeklyMinutes: Int?
    let dailyRevisions: [ProjectDailyGoalRevision]
    let weeklyRevisions: [ProjectWeeklyGoalRevision]
}

struct ProjectSettingsDraft {
    enum ScheduledWeeklyGoalEdit: Equatable {
        case set(Int?)
        case cancel
    }

    let projectID: UUID
    let isNew: Bool
    let createdOn: LocalDay
    let createdWeek: LocalDay
    let baseline: ProjectSettingsBaseline?

    var name: String
    var status: ProjectStatus
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var dailySchedule: [Int]?
    var weeklyMinutes: Int?
    var scheduledWeeklyEdits: [LocalDay: ScheduledWeeklyGoalEdit] = [:]

    var hasChanges: Bool {
        guard let baseline else { return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return name.trimmingCharacters(in: .whitespacesAndNewlines) != baseline.name || status != baseline.status
            || focusMinutes != baseline.focusMinutes
            || shortBreakMinutes != baseline.shortBreakMinutes
            || longBreakMinutes != baseline.longBreakMinutes
            || dailySchedule != baseline.dailySchedule
            || weeklyMinutes != baseline.weeklyMinutes
            || !scheduledWeeklyEdits.isEmpty
    }

    mutating func setScheduledWeeklyGoal(_ minutes: Int?, for day: LocalDay) {
        let original = baseline?.weeklyRevisions.first { $0.effectiveFrom == day }?.minutes
        if original == minutes { scheduledWeeklyEdits.removeValue(forKey: day) }
        else { scheduledWeeklyEdits[day] = .set(minutes) }
    }

    mutating func cancelScheduledWeeklyGoal(for day: LocalDay) {
        scheduledWeeklyEdits[day] = .cancel
    }

    var scheduledWeeklyRevisions: [ProjectWeeklyGoalRevision] {
        guard let baseline else { return [] }
        var result = baseline.weeklyRevisions.filter { $0.effectiveFrom > createdWeek }
        for (day, edit) in scheduledWeeklyEdits {
            result.removeAll { $0.effectiveFrom == day }
            if case .set(let minutes) = edit {
                result.append(ProjectWeeklyGoalRevision(projectID: projectID, effectiveFrom: day, minutes: minutes))
            }
        }
        return result.sorted { $0.effectiveFrom < $1.effectiveFrom }
    }
}

enum ProjectSettingsPage: Hashable {
    case daily
    case dailyTarget(title: String, indices: [Int])
    case weekly
    case weeklyTarget
    case scheduledWeekly(LocalDay)
}
