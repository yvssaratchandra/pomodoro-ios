import SwiftUI

struct SessionPlanEditor: View {
    let text: String
    let commit: (String) -> Result<Void, Error>
    @State private var draft: SessionPlanDraft
    @State private var composerText = ""
    @State private var editing: SessionPlanDraft.Row?
    @State private var error: String?
    @State private var confirmingDiscard = false
    @FocusState private var textFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(text: String, commit: @escaping (String) -> Result<Void, Error>) {
        self.text = text
        self.commit = commit
        _draft = State(initialValue: SessionPlanDraft(text: text))
    }

    private var hasDraft: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var canAdd: Bool { (try? draft.candidate(for: .add(composerText))) != nil }
    private var proposedCount: Int {
        (draft.rows.map(\.text) + SessionPlanText.items(from: composerText)).joined(separator: "\n").count
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(draft.rows) { row in
                        taskRow(row).id(row.id)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer {
                        guard let id = apply(.add(composerText)) else { return }
                        composerText = ""
                        Task { @MainActor in
                            await Task.yield()
                            textFocused = true
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
            }
            .appScreen()
            .navigationTitle("Session plan")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if hasDraft { confirmingDiscard = true } else { dismiss() }
                    }.accessibilityIdentifier("plan.done")
                }
            }
            .interactiveDismissDisabled(hasDraft)
            .sheet(item: $editing, onDismiss: restoreFocus) { row in
                SessionPlanTaskEditor(row: row, draft: draft) { value in
                    do {
                        _ = try draft.apply(.edit(row.id, value), commit: commit)
                        error = nil
                        return .success(())
                    } catch { return .failure(error) }
                }
            }
            .confirmationDialog("Discard this draft?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) {
                    composerText = ""
                    dismiss()
                }
                Button("Keep editing", role: .cancel, action: restoreFocus)
            }
            .onChange(of: text) { _, value in
                draft.reconcile(text: value)
                if let editing, !draft.rows.contains(where: { $0.id == editing.id }) {
                    self.editing = nil
                    error = SessionPlanDraft.EditError.missingTask.localizedDescription
                }
            }
            .task { textFocused = true }
        }
    }

    private func composer(onAdd: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Add a task…", text: $composerText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($textFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("plan.composer")
                Button(action: onAdd) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!canAdd)
                .accessibilityLabel("Add task")
                .accessibilityIdentifier("plan.add")
            }
            if proposedCount >= 230 {
                Text("\(proposedCount) / 280")
                    .font(.caption)
                    .foregroundStyle(proposedCount > 280 ? Color.red : Color.secondary)
            }
            if proposedCount > 280 {
                Text("Session plans can contain up to 280 characters.")
                    .font(.caption).foregroundStyle(.red)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
    }

    private func taskRow(_ row: SessionPlanDraft.Row) -> some View {
        Button {
            textFocused = false
            editing = row
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").accessibilityHidden(true)
                Text(row.text).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.text)
        .swipeActions(allowsFullSwipe: false) {
            Button("Delete", role: .destructive) { _ = apply(.delete(row.id)) }
        }
        .accessibilityActions {
            Button("Delete") { _ = apply(.delete(row.id)) }
        }
    }

    private func apply(_ mutation: SessionPlanDraft.Mutation) -> UUID? {
        do {
            let id = try draft.apply(mutation, commit: commit)
            error = nil
            return id
        } catch {
            self.error = error.localizedDescription
            restoreFocus()
            return nil
        }
    }

    private func restoreFocus() {
        Task { @MainActor in
            await Task.yield()
            textFocused = true
        }
    }
}

private struct SessionPlanTaskEditor: View {
    let row: SessionPlanDraft.Row
    let draft: SessionPlanDraft
    let commit: (String) -> Result<Void, Error>
    @State private var text: String
    @State private var error: String?
    @FocusState private var textFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(row: SessionPlanDraft.Row, draft: SessionPlanDraft, commit: @escaping (String) -> Result<Void, Error>) {
        self.row = row
        self.draft = draft
        self.commit = commit
        _text = State(initialValue: row.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($textFocused)
                    .accessibilityIdentifier("plan.task.edit")
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .appScreen()
            .navigationTitle("Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("plan.task.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        switch commit(text) {
                        case .success: dismiss()
                        case .failure(let error): self.error = error.localizedDescription
                        }
                    }
                    .disabled((try? draft.candidate(for: .edit(row.id, text))) == nil)
                    .accessibilityIdentifier("plan.task.save")
                }
            }
            .task { textFocused = true }
        }
        .presentationDetents([.medium, .large])
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
