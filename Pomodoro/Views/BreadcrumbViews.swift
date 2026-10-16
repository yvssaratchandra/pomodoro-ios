import SwiftUI

struct BreadcrumbEditor: View {
    let store: AppStore
    var sessionID: UUID?
    var projectID: UUID?
    var promote = false
    @State private var draft: String
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(store: AppStore, sessionID: UUID? = nil, projectID: UUID? = nil, promote: Bool = false) {
        self.store = store; self.sessionID = sessionID; self.projectID = projectID; self.promote = promote
        _draft = State(initialValue: sessionID.flatMap { id in store.state.sessions.first { $0.id == id }?.nextStep }
            ?? projectID.flatMap { id in store.state.projects.first { $0.id == id }?.breadcrumb?.text } ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Where will you pick up next time?", text: $draft, axis: .vertical).lineLimit(3...8).accessibilityIdentifier("breadcrumb.text")
                Text("\(draft.count) / 280 characters").foregroundStyle(.secondary)
            }.appScreen().navigationTitle("Next time")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved: Bool
                        if let sessionID { saved = store.saveNextStep(sessionID: sessionID, text: draft, promote: promote) }
                        else if let projectID { saved = store.editProjectBreadcrumb(projectID: projectID, text: draft) }
                        else { return }
                        if saved { dismiss() } else { error = store.errorMessage; store.errorMessage = nil }
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).count > 280)
                        .accessibilityIdentifier("breadcrumb.save")
                }
            }
            .alert("Unable to save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
}

struct BreadcrumbCard: View {
    @Bindable var store: AppStore
    let project: Project
    var useAsIntention: ((String) -> Void)?
    @State private var editing = false
    var body: some View {
        if let breadcrumb = project.breadcrumb {
            VStack(alignment: .leading, spacing: 10) {
                Label("Next time", systemImage: "arrow.turn.down.right").font(.headline)
                Text(breadcrumb.text)
                if let useAsIntention { Button("Use as intention") { useAsIntention(breadcrumb.text) } }
                HStack {
                    Button("Edit") { editing = true }
                    Button("Clear", role: .destructive) { _ = store.editProjectBreadcrumb(projectID: project.id, text: "") }
                }
            }
            .sheet(isPresented: $editing) { BreadcrumbEditor(store: store, projectID: project.id) }
        }
    }
}
