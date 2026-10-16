import Foundation

struct ProjectBreadcrumb: Codable, Equatable {
    var text: String
    var updatedAt: Date
    var originSessionID: UUID?
}
