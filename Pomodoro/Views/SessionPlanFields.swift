import SwiftUI

struct SessionPlanFields: View {
    @Binding var draft: SessionPlanDraft
    @FocusState private var focusedRow: UUID?

    var body: some View {
        Section("What do you want to achieve?") {
            ForEach(draft.rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").accessibilityHidden(true)
                    TextField("Add a task…", text: binding(for: row.id), axis: .vertical)
                        .focused($focusedRow, equals: row.id)
                        .accessibilityIdentifier("intention.task")
                }
                .swipeActions {
                    if !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Delete", role: .destructive) { remove(row.id) }
                    }
                }
                .accessibilityActions {
                    if !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Delete") { remove(row.id) }
                    }
                }
            }
            if draft.characterCount >= 230 {
                Text("\(draft.characterCount) / 280")
                    .foregroundStyle(draft.characterCount > 280 ? Color.red : Color.secondary)
            }
        }
        .onAppear { if let first = draft.rows.first { focus(first.id) } }
        .onChange(of: focusedRow) { old, _ in
            if let old { draft.endEditing(id: old) }
        }
    }

    private func binding(for id: UUID) -> Binding<String> {
        Binding(get: { draft.rows.first { $0.id == id }?.text ?? "" }, set: { value in
            if let destination = draft.applyEdit(id: id, text: value) { focus(destination) }
        })
    }

    private func remove(_ id: UUID) {
        let wasFocused = focusedRow == id
        let destination = draft.remove(id: id)
        if wasFocused { focus(destination) }
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
