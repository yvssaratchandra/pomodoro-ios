import Foundation

enum SessionPlanText {
    static func items(from text: String?) -> [String] {
        (text ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func serialize(_ items: [String]) throws -> String? {
        try SessionText.normalize(items.flatMap { self.items(from: $0) }.joined(separator: "\n"))
    }
}
