import Foundation

struct CapturedThought: Identifiable, Codable, Equatable {
    var id = UUID()
    var projectID: UUID
    var originSessionID: UUID?
    var createdAt: Date
    var text: String
    var completedAt: Date?
}
struct ThoughtCaptureContext: Identifiable, Equatable {
    let id = UUID()
    let projectID: UUID
    let originSessionID: UUID?
}
