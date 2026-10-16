import SwiftUI

struct BreadcrumbEditor: View {
    let store: AppStore
    var sessionID: UUID?
    var projectID: UUID?
    var promote = false
    @State private var draft: String
    @State private var original: String
    @State private var error: String?
    @State private var confirmingDiscard = false
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore, sessionID: UUID? = nil, projectID: UUID? = nil, promote: Bool = false) {
        self.store = store; self.sessionID = sessionID; self.projectID = projectID; self.promote = promote
        let initial = sessionID.flatMap { id in store.state.sessions.first { $0.id == id }?.nextStep }
            ?? projectID.flatMap { id in store.state.projects.first { $0.id == id }?.breadcrumb?.text } ?? ""
        _draft = State(initialValue: initial)
        _original = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Where will you pick up?", text: $draft, axis: .vertical)
                    .lineLimit(3...8).focused($focused).accessibilityIdentifier("breadcrumb.text")
                if draft.count >= 230 { Text("\(draft.count) / 280").foregroundStyle(.secondary) }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }.appScreen().navigationTitle("Next step")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if draft == original { dismiss() } else { confirmingDiscard = true } }
                }
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
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
            .interactiveDismissDisabled(draft != original)
            .onAppear { focused = true }
        }
    }
}

struct BreadcrumbCard: View {
    @Bindable var store: AppStore
    let project: Project
    var useAsIntention: ((String) -> Void)?
    @State private var showingDetails = false

    var body: some View {
        if let breadcrumb = project.breadcrumb {
            Button { showingDetails = true } label: {
                HStack {
                    Label("Next step", systemImage: "arrow.turn.down.right")
                    Spacer()
                    Text(breadcrumb.text).lineLimit(1).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("focus.nextStep")
            .sheet(isPresented: $showingDetails) {
                BreadcrumbDetailSheet(store: store, projectID: project.id, useAsIntention: useAsIntention)
            }
        }
    }
}

private struct BreadcrumbDetailSheet: View {
    @Bindable var store: AppStore
    let projectID: UUID
    var useAsIntention: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmingClear = false
    @State private var error: String?
    private var breadcrumb: ProjectBreadcrumb? {
        store.state.projects.first { $0.id == projectID }?.breadcrumb
    }

    var body: some View {
        NavigationStack {
            Form {
                if let breadcrumb {
                    Section("Next step") { Text(breadcrumb.text) }
                    Section {
                        if let useAsIntention {
                            Button("Use for this session") {
                                useAsIntention(breadcrumb.text)
                                dismiss()
                            }
                        }
                        Button("Edit") { editing = true }
                        Button("Clear", role: .destructive) { confirmingClear = true }
                    }
                }
            }
            .appScreen()
            .navigationTitle("Next step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $editing) { BreadcrumbEditor(store: store, projectID: projectID) }
            .confirmationDialog("Clear next step?", isPresented: $confirmingClear) {
                Button("Clear next step", role: .destructive) {
                    if store.editProjectBreadcrumb(projectID: projectID, text: "") { dismiss() }
                    else { error = store.errorMessage; store.errorMessage = nil }
                }
            }
            .alert("Unable to clear next step", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
}
