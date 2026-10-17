import SwiftUI

struct SessionPlanRow: Identifiable {
    let id: UUID
    var text: String

    init(text: String = "", id: UUID = UUID()) {
        self.id = id
        self.text = text
    }

    static func initialRows(from text: String) -> [SessionPlanRow] {
        let items = SessionPlanText.items(from: text)
        return items.isEmpty ? [SessionPlanRow()] : items.map { SessionPlanRow(text: $0) }
    }
}

struct SessionPlanFields: View {
    @Binding var rows: [SessionPlanRow]
    @Binding var edited: Bool
    @FocusState private var focusedRow: UUID?

    private var characterCount: Int {
        rows.flatMap { SessionPlanText.items(from: $0.text) }.joined(separator: "\n").count
    }

    var body: some View {
        Section("What do you want to achieve?") {
            ForEach(rows) { row in
                HStack(alignment: .top) {
                    Text("•").padding(.top, 11).accessibilityHidden(true)
                    TextField("Task", text: binding(for: row.id), axis: .vertical)
                        .padding(.vertical, 11)
                        .focused($focusedRow, equals: row.id)
                        .accessibilityIdentifier("intention.task")
                    Button { remove(row.id) } label: {
                        Image(systemName: "minus.circle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(row.text.isEmpty ? "Remove task" : "Remove \(row.text)")
                    .accessibilityIdentifier("intention.removeTask")
                }
            }
            Button {
                if let last = rows.last, last.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    focus(last.id)
                } else {
                    let row = SessionPlanRow()
                    rows.append(row)
                    edited = true
                    focus(row.id)
                }
            } label: { Label("Add a task", systemImage: "plus") }
            .frame(minHeight: 44)
            .accessibilityIdentifier("intention.addTask")
            if characterCount >= 230 {
                Text("\(characterCount) / 280")
                    .foregroundStyle(characterCount > 280 ? Color.red : Color.secondary)
            }
        }
        .onAppear { if let first = rows.first { focus(first.id) } }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(get: { rows.first { $0.id == id }?.text ?? "" }, set: { value in
            guard let index = rows.firstIndex(where: { $0.id == id }), rows[index].text != value else { return }
            edited = true
            let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let lines = normalized.components(separatedBy: "\n")
            rows[index].text = lines[0]
            if lines.count > 1 {
                let inserted = lines.dropFirst().map { SessionPlanRow(text: $0) }
                rows.insert(contentsOf: inserted, at: index + 1)
                if let last = inserted.last { focus(last.id) }
            }
        })
    }

    private func remove(_ id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows.remove(at: index)
        if rows.isEmpty { rows = [SessionPlanRow()] }
        edited = true
        focus(rows[min(index, rows.count - 1)].id)
    }

    private func focus(_ id: UUID) {
        Task { @MainActor in
            await Task.yield()
            focusedRow = id
        }
    }
}

struct SessionPlanPreview: View {
    let text: String
    var maximumItems: Int? = nil

    var body: some View {
        let items = SessionPlanText.items(from: text)
        let visible = Array(items.prefix(maximumItems ?? items.count))
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").accessibilityHidden(true)
                    Text(item).lineLimit(maximumItems == nil ? nil : 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item)
            }
            if items.count > visible.count {
                Text("+\(items.count - visible.count) more").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.joined(separator: ". ") + (items.count > visible.count ? ". +\(items.count - visible.count) more" : ""))
    }
}
