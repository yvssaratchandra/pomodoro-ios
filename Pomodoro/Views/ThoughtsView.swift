import SwiftUI

struct ThoughtEditor: View {
    let store: AppStore
    let context: ThoughtCaptureContext?
    let thoughtID: UUID?
    @State private var draft: String
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(store: AppStore, context: ThoughtCaptureContext? = nil, thoughtID: UUID? = nil) {
        self.store = store; self.context = context; self.thoughtID = thoughtID
        _draft = State(initialValue: thoughtID.flatMap { id in store.state.thoughts.first { $0.id == id }?.text } ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                if let context { LabeledContent("Project", value: store.projectName(context.projectID)) }
                TextField("Save this thought for later", text: $draft, axis: .vertical)
                    .lineLimit(4...12).accessibilityIdentifier("thought.text")
                Text("\(draft.count) / 500 characters").foregroundStyle(.secondary)
            }.appScreen().navigationTitle(thoughtID == nil ? "Capture thought" : "Edit thought")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved: Bool
                        if let thoughtID { saved = store.editThought(id: thoughtID, text: draft) }
                        else if let context { saved = store.captureThought(context: context, text: draft) }
                        else { return }
                        if saved { dismiss() } else { error = store.errorMessage; store.errorMessage = nil }
                    }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.trimmingCharacters(in: .whitespacesAndNewlines).count > 500)
                        .accessibilityIdentifier("thought.save")
                }
            }
            .alert("Unable to save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
}

struct ThoughtsView: View {
    @Bindable var store: AppStore
    @Bindable var navigation: AppNavigation
    @State private var editing: CapturedThought?
    @State private var deleting: CapturedThought?
    private var thoughts: [CapturedThought] {
        store.state.thoughts.filter {
            (navigation.thoughtProjectID == nil || $0.projectID == navigation.thoughtProjectID)
                && (navigation.thoughtFilter == 0 || (navigation.thoughtFilter == 1 ? $0.completedAt == nil : $0.completedAt != nil))
        }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Thoughts", selection: $navigation.thoughtFilter) {
                        Text("All").tag(0); Text("Open").tag(1); Text("Done").tag(2)
                    }.pickerStyle(.segmented)
                    Picker("Project", selection: $navigation.thoughtProjectID) {
                        Text("All projects").tag(Optional<UUID>.none)
                        ForEach(store.state.projects) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                ForEach(thoughts) { thought in
                    HStack(alignment: .top, spacing: 12) {
                        Button { _ = store.setThoughtCompleted(id: thought.id, completed: thought.completedAt == nil) } label: {
                            Image(systemName: thought.completedAt == nil ? "square" : "checkmark.square.fill")
                                .font(.title2).frame(width: 44, height: 44)
                        }.buttonStyle(.borderless)
                            .accessibilityLabel(thought.completedAt == nil ? "Mark thought done" : "Mark thought open")
                            .accessibilityValue(thought.completedAt == nil ? "Open" : "Done")
                            .accessibilityIdentifier("thought.check")
                        Button { editing = thought } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(thought.text).strikethrough(thought.completedAt != nil).foregroundStyle(.primary)
                                Text(store.projectName(thought.projectID)).font(.caption).foregroundStyle(.secondary)
                                Text(thought.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                if let origin = thought.originSessionID, store.state.activeTimer?.id != origin,
                                   !store.state.sessions.contains(where: { $0.id == origin }) {
                                    Text("Session removed").font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { deleting = thought } }
                    .contextMenu {
                        Button("Edit") { editing = thought }
                        Button("Delete thought", role: .destructive) { deleting = thought }
                    }
                }
                if thoughts.isEmpty { ContentUnavailableView("No Thoughts", systemImage: "text.bubble", description: Text("Capture a thought during focus to come back to it later.")) }
            }
            .appScreen().navigationTitle("Thoughts")
            .sheet(item: $editing) { ThoughtEditor(store: store, thoughtID: $0.id) }
            .alert("Delete this thought?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete", role: .destructive) { if let deleting { _ = store.deleteThought(id: deleting.id) }; deleting = nil }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("This removes the thought permanently.") }
            .onChange(of: store.state.projects.map(\.id)) { _, ids in
                if let id = navigation.thoughtProjectID, !ids.contains(id) { navigation.thoughtProjectID = nil }
            }
        }
    }
}
