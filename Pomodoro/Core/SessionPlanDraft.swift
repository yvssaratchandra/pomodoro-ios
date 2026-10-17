import Foundation

/// Accepted tasks. Candidate changes are adopted only after their complete text is saved.
struct SessionPlanDraft {
    struct Row: Identifiable, Equatable {
        let id: UUID
        var text: String

        init(id: UUID = UUID(), text: String) {
            self.id = id
            self.text = text
        }
    }

    enum Mutation {
        case add(String)
        case edit(UUID, String)
        case delete(UUID)
    }

    enum EditError: LocalizedError {
        case blankTask
        case missingTask

        var errorDescription: String? {
            switch self {
            case .blankTask: return "Enter a task before saving."
            case .missingTask: return "This task is no longer in the session plan."
            }
        }
    }

    struct Candidate {
        let rows: [Row]
        let text: String
    }

    private(set) var rows: [Row]

    init(text: String) {
        rows = SessionPlanText.items(from: text).map { Row(text: $0) }
    }

    var characterCount: Int { rows.map(\.text).joined(separator: "\n").count }

    func candidate(for mutation: Mutation) throws -> Candidate {
        var result = rows
        switch mutation {
        case .add(let text):
            let items = SessionPlanText.items(from: text)
            guard !items.isEmpty else { throw EditError.blankTask }
            result.append(contentsOf: items.map { Row(text: $0) })
        case .edit(let id, let text):
            guard let index = result.firstIndex(where: { $0.id == id }) else { throw EditError.missingTask }
            let items = SessionPlanText.items(from: text)
            guard let first = items.first else { throw EditError.blankTask }
            let replacements = [Row(id: id, text: first)] + items.dropFirst().map { Row(text: $0) }
            result.replaceSubrange(index...index, with: replacements)
        case .delete(let id):
            guard let index = result.firstIndex(where: { $0.id == id }) else { throw EditError.missingTask }
            result.remove(at: index)
        }
        return Candidate(rows: result, text: try SessionPlanText.serialize(result.map(\.text)) ?? "")
    }

    /// Returns the last newly inserted task so the editor can reveal it after saving.
    @discardableResult
    mutating func apply(_ mutation: Mutation, commit: (String) -> Result<Void, Error>) throws -> UUID? {
        let candidate = try candidate(for: mutation)
        try commit(candidate.text).get()
        let previousIDs = Set(rows.map(\.id))
        rows = candidate.rows
        return rows.last(where: { !previousIDs.contains($0.id) })?.id
    }

    /// Reuses identities for surviving text, including repeated tasks in their existing order.
    mutating func reconcile(text: String) {
        var available = rows
        rows = SessionPlanText.items(from: text).map { text in
            if let index = available.firstIndex(where: { $0.text == text }) {
                return available.remove(at: index)
            }
            return Row(text: text)
        }
    }
}
