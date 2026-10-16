import Foundation

struct CapturedThought: Identifiable, Codable, Equatable {
    var id = UUID()
    var projectID: UUID?
    var originSessionID: UUID?
    var createdAt: Date
    var text: String
    var completedAt: Date?
}
struct ThoughtCaptureContext: Identifiable, Equatable {
    let id = UUID()
    let projectID: UUID?
    let originSessionID: UUID?
}

enum ThoughtProjectFilter: Hashable {
    case all, unassigned, project(UUID)

    func includes(_ id: UUID?) -> Bool {
        switch self {
        case .all: return true
        case .unassigned: return id == nil
        case .project(let selected): return id == selected
        }
    }
}
