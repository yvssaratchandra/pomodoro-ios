import Foundation

enum ThoughtEngine {
    static func capture(_ state: inout AppSnapshot, context: ThoughtCaptureContext, text: String, now: Date) throws {
        guard state.projects.contains(where: { $0.id == context.projectID }) else { throw AppError.invalid("This project is no longer available.") }
        guard let text = try SessionText.normalize(text, limit: 500) else { throw AppError.invalid("Enter a thought before saving.") }
        state.thoughts.append(CapturedThought(projectID: context.projectID, originSessionID: context.originSessionID, createdAt: now, text: text))
    }
    static func edit(_ state: inout AppSnapshot, id: UUID, text: String) throws {
        guard let i = state.thoughts.firstIndex(where: { $0.id == id }) else { throw AppError.invalid("This thought is no longer available.") }
        guard let text = try SessionText.normalize(text, limit: 500) else { throw AppError.invalid("Enter a thought before saving.") }
        state.thoughts[i].text = text
    }
    static func setCompleted(_ state: inout AppSnapshot, id: UUID, completed: Bool, now: Date) throws {
        guard let i = state.thoughts.firstIndex(where: { $0.id == id }) else { throw AppError.invalid("This thought is no longer available.") }
        if completed { if state.thoughts[i].completedAt == nil { state.thoughts[i].completedAt = max(now, state.thoughts[i].createdAt) } }
        else { state.thoughts[i].completedAt = nil }
    }
}
