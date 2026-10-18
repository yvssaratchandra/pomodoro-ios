import SwiftUI

struct IntentionEditor: View {
    let store: AppStore
    let sessionID: UUID
    let active: Bool

    private var text: String {
        if active {
            return store.state.activeTimer.flatMap { $0.id == sessionID ? $0.intention : nil } ?? ""
        }
        return store.state.sessions.first { $0.id == sessionID }?.intention ?? ""
    }

    var body: some View {
        SessionPlanEditor(text: text) { value in
            if store.editIntention(id: sessionID, active: active, text: value) { return .success(()) }
            let error = PlanSaveError(message: store.errorMessage ?? "Your changes could not be saved. Try again.")
            store.errorMessage = nil
            return .failure(error)
        }
    }
}

struct SessionDetailView: View {
    @Bindable var store: AppStore
    let sessionID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var editingIntention = false
    @State private var editingBreadcrumb = false
    @State private var confirmingPlanReplacement = false
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
                        Button(session.intention == nil ? "Plan this session" : "Edit session plan") { editingIntention = true }
                    }
                    Section("Next session") {
                        if let note = session.nextStep { Text(note) }
                        Button(session.nextStep == nil ? "Plan next session" : "Edit next session plan") { editingBreadcrumb = true }
                        if let note = session.nextStep {
                            Button("Use for next session") { useForNextSession(note, projectID: session.projectID) }
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
                .sheet(isPresented: $editingBreadcrumb) { SessionNextStepEditor(store: store, sessionID: sessionID) }
                .confirmationDialog("Replace the current session plan?", isPresented: $confirmingPlanReplacement) {
                    Button("Replace plan", role: .destructive) {
                        guard let session = store.state.sessions.first(where: { $0.id == sessionID }) else { return }
                        assignNextStep(session.nextStep, projectID: session.projectID)
                    }
                    Button("Cancel", role: .cancel) { }
                }
                .alert("Unable to Complete Action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK") { error = nil }
                } message: { Text(error ?? "") }
            } else { ContentUnavailableView("Session Removed", systemImage: "timer") }
        }.navigationTitle("Session").navigationBarTitleDisplayMode(.inline)
    }

    private func useForNextSession(_ text: String, projectID: UUID) {
        if let existing = store.state.projects.first(where: { $0.id == projectID })?.breadcrumb,
           existing.text != text {
            confirmingPlanReplacement = true
        } else {
            assignNextStep(text, projectID: projectID)
        }
    }

    private func assignNextStep(_ text: String?, projectID: UUID) {
        if !store.setPendingPlan(projectID: projectID, text: text ?? "") {
            error = store.errorMessage
            store.errorMessage = nil
        }
    }
}

private struct SessionNextStepEditor: View {
    let store: AppStore
    let sessionID: UUID

    private var text: String {
        store.state.sessions.first(where: { $0.id == sessionID })?.nextStep ?? ""
    }

    var body: some View {
        SessionPlanEditor(text: text) { value in
            guard store.saveNextStep(sessionID: sessionID, text: value, promote: false) else {
                let error = PlanSaveError(message: store.errorMessage ?? "Your plan could not be saved. Try again.")
                store.errorMessage = nil
                return .failure(error)
            }
            return .success(())
        }
    }
}
