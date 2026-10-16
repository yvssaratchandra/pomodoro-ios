import SwiftUI

struct IntentionEditor: View {
    let store: AppStore
    let sessionID: UUID
    let active: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @State private var error: String?

    init(store: AppStore, sessionID: UUID, active: Bool) {
        self.store = store
        self.sessionID = sessionID
        self.active = active
        _draft = State(initialValue: active ? store.state.activeTimer?.intention ?? "" : store.state.sessions.first { $0.id == sessionID }?.intention ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("What are you working on?", text: $draft, axis: .vertical)
                    .lineLimit(3...8).accessibilityIdentifier("intention.text")
                Text("\(draft.count) / 280 characters").foregroundStyle(.secondary)
            }
            .appScreen().navigationTitle("Session intention")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.editIntention(id: sessionID, active: active, text: draft) { dismiss() }
                        else { error = store.errorMessage; store.errorMessage = nil }
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).count > 280)
                        .accessibilityIdentifier("intention.save")
                }
            }
            .alert("Unable to save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}

struct SessionDetailView: View {
    @Bindable var store: AppStore
    let sessionID: UUID
    @State private var editingIntention = false
    @State private var editingBreadcrumb = false
    var body: some View {
        Group {
            if let session = store.state.sessions.first(where: { $0.id == sessionID }) {
                Form {
                    SessionRow(session: session, name: store.projectName(session.projectID))
                    Section("Intention") {
                        Text(session.intention ?? "No intention recorded")
                        Button("Edit intention") { editingIntention = true }
                    }
                    Section("Next time") {
                        Text(session.nextStep ?? "No next step recorded")
                        Button("Edit next step") { editingBreadcrumb = true }
                        if let note = session.nextStep {
                            Button("Use as project's next step") { _ = store.saveNextStep(sessionID: session.id, text: note, promote: true) }
                        }
                    }
                }.appScreen()
                .sheet(isPresented: $editingIntention) { IntentionEditor(store: store, sessionID: sessionID, active: false) }
                .sheet(isPresented: $editingBreadcrumb) { BreadcrumbEditor(store: store, sessionID: sessionID) }
            } else { ContentUnavailableView("Session removed", systemImage: "timer") }
        }.navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
    }
}
