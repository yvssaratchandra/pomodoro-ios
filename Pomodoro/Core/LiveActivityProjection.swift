import Foundation

struct LiveActivityProjection: Codable, Equatable, Hashable {
    let id: UUID
    let projectID: UUID?
    let kind: String
    let startedAt: Date
    let deadline: Date
    let projectName: String?
    let intention: String?
    var title: String { kind == "focus" ? "Focus" : kind == "longBreak" ? "Long break" : "Short break" }

    init?(state: AppSnapshot) {
        guard let timer = state.activeTimer else { return nil }
        id = timer.id
        projectID = timer.projectID
        kind = timer.kind.rawValue
        startedAt = timer.startedAt
        deadline = timer.deadline
        projectName = state.settings.showProjectNameOnLockScreen ? Self.preview(state.projects.first { $0.id == timer.projectID }?.name, byteLimit: 256) : nil
        intention = state.settings.showIntentionOnLockScreen ? Self.preview(timer.intention, byteLimit: 1024) : nil
    }
    var actionRoute: AppRoute {
        if kind != "focus", let projectID { return .planNextSession(projectID: projectID) }
        return kind == "focus" ? .captureThought(sessionID: id) : .timer
    }

    // Keep display text within ActivityKit's payload budget, including multi-scalar characters.
    private static func preview(_ text: String?, byteLimit: Int) -> String? {
        guard let text, text.utf8.count > byteLimit else { return text }
        var result = ""
        for character in text {
            guard result.utf8.count + String(character).utf8.count <= byteLimit - 3 else { break }
            result.append(character)
        }
        return result + "…"
    }
}
