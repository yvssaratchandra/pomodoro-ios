import SwiftUI

struct DraftSessionNoteEditor: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var draft: String
    @State private var confirmingDiscard = false

    init(text: Binding<String>) {
        _text = text
        _draft = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What will you work on?", text: $draft, axis: .vertical)
                    .lineLimit(3...8).focused($focused).accessibilityIdentifier("intention.text")
                if draft.count >= 230 { Text("\(draft.count) / 280").foregroundStyle(.secondary) }
            }
            .appScreen().navigationTitle("This session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { text = draft; dismiss() }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).count > 280)
                        .accessibilityIdentifier("intention.save")
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
            .interactiveDismissDisabled(draft != text)
            .onAppear { focused = true }
        }
    }

    private func cancel() { if draft == text { dismiss() } else { confirmingDiscard = true } }
}

struct IntentionEditor: View {
    let store: AppStore
    let sessionID: UUID
    let active: Bool
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var draft: String
    @State private var original: String
    @State private var error: String?
    @State private var confirmingDiscard = false

    init(store: AppStore, sessionID: UUID, active: Bool) {
        self.store = store
        self.sessionID = sessionID
        self.active = active
        let initial = active ? store.state.activeTimer?.intention ?? "" : store.state.sessions.first { $0.id == sessionID }?.intention ?? ""
        _draft = State(initialValue: initial)
        _original = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("What will you work on?", text: $draft, axis: .vertical)
                    .lineLimit(3...8).focused($focused).accessibilityIdentifier("intention.text")
                if draft.count >= 230 { Text("\(draft.count) / 280").foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .appScreen().navigationTitle("This session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if draft == original { dismiss() } else { confirmingDiscard = true } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.editIntention(id: sessionID, active: active, text: draft) { dismiss() }
                        else { error = store.errorMessage; store.errorMessage = nil }
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).count > 280)
                        .accessibilityIdentifier("intention.save")
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
            .interactiveDismissDisabled(draft != original)
            .onAppear { focused = true }
        }
    }
}

struct SessionDetailView: View {
    @Bindable var store: AppStore
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var editingIntention = false
    @State private var editingBreadcrumb = false
    @State private var error: String?

    var body: some View {
        Group {
            if let session = store.state.sessions.first(where: { $0.id == sessionID }) {
                Form {
                    Section {
                        LabeledContent("Project", value: store.projectName(session.projectID))
                        LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Focus time", value: DurationText.work(session.duration))
                        if session.outcome == .interrupted { Text("Ended early").foregroundStyle(.secondary) }
                    }
                    Section("This session") {
                        if let note = session.intention { Text(note) }
                        Button(session.intention == nil ? "Plan this session" : "Edit this session") { editingIntention = true }
                    }
                    Section("Next time") {
                        if let note = session.nextStep { Text(note) }
                        Button(session.nextStep == nil ? "Plan next time" : "Edit next time") { editingBreadcrumb = true }
                        if let note = session.nextStep {
                            Button("Set as project reminder") {
                                if !store.saveNextStep(sessionID: session.id, text: note, promote: true) {
                                    error = store.errorMessage
                                    store.errorMessage = nil
                                }
                            }
                        }
                    }
                }.appScreen()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                if store.deleteSession(sessionID) { dismiss() }
                                else { error = store.errorMessage; store.errorMessage = nil }
                            } label: { Label("Delete Session", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More session actions") }
                    }
                }
                .sheet(isPresented: $editingIntention) { IntentionEditor(store: store, sessionID: sessionID, active: false) }
                .sheet(isPresented: $editingBreadcrumb) { BreadcrumbEditor(store: store, sessionID: sessionID) }
                .alert("Unable to Complete Action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
            } else { ContentUnavailableView("Session Removed", systemImage: "timer") }
        }.navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
    }
}
