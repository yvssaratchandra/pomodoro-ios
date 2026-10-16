import Foundation

enum SessionText {
    static func normalize(_ text: String?, limit: Int = 280) throws -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        guard value.count <= limit else { throw AppError.invalid("Use \(limit) characters or fewer.") }
        return value
    }
}
