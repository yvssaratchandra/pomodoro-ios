import Foundation

struct LiveActivityProjection: Codable, Equatable, Hashable {
    let id: UUID
    let kind: String
    let startedAt: Date
    let deadline: Date
    let projectName: String?
    let intention: String?
    var title: String { kind == "focus" ? "Focus" : kind == "longBreak" ? "Long break" : "Short break" }

    init?(state: AppSnapshot) {
        guard let timer = state.activeTimer else { return nil }
        id = timer.id
        kind = timer.kind.rawValue
        startedAt = timer.startedAt
        deadline = timer.deadline
        projectName = state.settings.showProjectNameOnLockScreen ? state.projects.first { $0.id == timer.projectID }?.name : nil
        intention = state.settings.showIntentionOnLockScreen ? timer.intention : nil
    }
}
