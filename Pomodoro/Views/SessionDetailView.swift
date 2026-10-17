import SwiftUI

struct DraftSessionNoteEditor: View {
    @Binding var text: String

    var body: some View {
        SessionPlanEditor(text: text) { value in
            text = value
            return .success(())
        }
    }
}

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

private struct PlanSaveError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
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
