import Foundation

struct SessionPlanDraft {
    struct Row: Identifiable {
        let id: UUID
        var text: String

        init(text: String = "") {
            id = UUID()
            self.text = text
        }
    }

    private(set) var rows: [Row]
    private let originalItems: [String]

    init(text: String) {
        originalItems = SessionPlanText.items(from: text)
        rows = originalItems.map { Row(text: $0) } + [Row()]
    }

    var hasChanges: Bool { meaningfulItems != originalItems }
    var characterCount: Int { meaningfulItems.joined(separator: "\n").count }

    private var meaningfulItems: [String] {
        rows.flatMap { SessionPlanText.items(from: $0.text) }
    }

    /// Returns a focus destination only when a newline advances to another task.
    mutating func applyEdit(id: UUID, text: String) -> UUID? {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.count > 1 else {
            rows[index].text = text
            ensurePlaceholder()
            return nil
        }
        let nonempty = lines.filter { !isEmpty($0) }
        guard let first = nonempty.first else {
            rows[index].text = lines[0]
            return nil
        }
        rows[index].text = first
        let inserted = nonempty.dropFirst().map { Row(text: $0) }
        rows.insert(contentsOf: inserted, at: index + 1)
        ensurePlaceholder()
        if let last = inserted.last { return last.id }
        return rows[index + 1].id
    }

    mutating func endEditing(id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }),
              index != rows.count - 1, isEmpty(rows[index].text) else { return }
        rows.remove(at: index)
    }

    mutating func remove(id: UUID) -> UUID {
        guard let index = rows.firstIndex(where: { $0.id == id }), index != rows.count - 1 else {
            return rows.last!.id
        }
        rows.remove(at: index)
        return rows[min(index, rows.count - 1)].id
    }

    func serialized() throws -> String? {
        try SessionPlanText.serialize(rows.map(\.text))
    }

    private mutating func ensurePlaceholder() {
        if let last = rows.last, !isEmpty(last.text) { rows.append(Row()) }
    }

    private func isEmpty(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
