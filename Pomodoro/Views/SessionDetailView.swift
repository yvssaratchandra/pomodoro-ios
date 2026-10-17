import SwiftUI

struct DraftSessionNoteEditor: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [SessionPlanRow]
    @State private var edited = false
    @State private var error: String?
    @State private var confirmingDiscard = false

    init(text: Binding<String>) {
        _text = text
        _rows = State(initialValue: SessionPlanRow.initialRows(from: text.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            Form {
                SessionPlanFields(rows: $rows, edited: $edited)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .appScreen().navigationTitle("This session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if edited { confirmingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.accessibilityIdentifier("intention.save")
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
            .interactiveDismissDisabled(edited)
        }
    }

    private func save() {
        guard edited else { dismiss(); return }
        do {
            text = try SessionPlanText.serialize(rows.map(\.text)) ?? ""
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct IntentionEditor: View {
    let store: AppStore
    let sessionID: UUID
    let active: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [SessionPlanRow]
    @State private var edited = false
    @State private var error: String?
    @State private var confirmingDiscard = false

    init(store: AppStore, sessionID: UUID, active: Bool) {
        self.store = store
        self.sessionID = sessionID
        self.active = active
        let initial = active ? store.state.activeTimer?.intention ?? "" : store.state.sessions.first { $0.id == sessionID }?.intention ?? ""
        _rows = State(initialValue: SessionPlanRow.initialRows(from: initial))
    }

    var body: some View {
        NavigationStack {
            Form {
                SessionPlanFields(rows: $rows, edited: $edited)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .appScreen().navigationTitle("This session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if edited { confirmingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.accessibilityIdentifier("intention.save")
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
            .interactiveDismissDisabled(edited)
        }
    }

    private func save() {
        guard edited else { dismiss(); return }
        do {
            let value = try SessionPlanText.serialize(rows.map(\.text))
            if store.editIntention(id: sessionID, active: active, text: value ?? "") { dismiss() }
            else { error = store.errorMessage; store.errorMessage = nil }
        } catch { self.error = error.localizedDescription }
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
                        if let note = session.intention { SessionPlanPreview(text: note) }
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
