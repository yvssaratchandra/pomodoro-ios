import SwiftUI

struct ThoughtCaptureView: View {
    let store: AppStore
    let context: ThoughtCaptureContext
    @State private var draft = ""
    @State private var composerVisible = true
    @State private var projectID: UUID?
    @State private var createdIDs: Set<UUID> = []
    @State private var editing: CapturedThought?
    @State private var error: String?
    @State private var confirmingDiscard = false
    @FocusState private var textFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore, context: ThoughtCaptureContext) {
        self.store = store
        self.context = context
        _projectID = State(initialValue: context.projectID)
    }

    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var thoughts: [CapturedThought] {
        store.state.thoughts.filter { thought in
            if let origin = context.originSessionID { return thought.originSessionID == origin }
            return createdIDs.contains(thought.id)
        }.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    if !thoughts.isEmpty {
                        Section {
                            ForEach(thoughts) { thought in thoughtRow(thought) }
                        }
                    }
                    Section {
                        if composerVisible {
                            TextField("What’s on your mind?", text: $draft, axis: .vertical)
                                .lineLimit(3...12)
                                .focused($textFocused)
                                .accessibilityIdentifier("thought.text")
                            if draft.count >= 450 {
                                Text("\(draft.count) / 500")
                                    .foregroundStyle(draft.count > 500 ? .red : .secondary)
                            }
                            if context.originSessionID == nil {
                                Picker("Project", selection: $projectID) {
                                    Text("Unassigned").tag(Optional<UUID>.none)
                                    ForEach(store.state.projects) { Text($0.name).tag(Optional($0.id)) }
                                }.accessibilityIdentifier("thought.project")
                            }
                            HStack {
                                Button {
                                    if hasDraft { confirmingDiscard = true } else { discardDraft() }
                                } label: {
                                    Text("Cancel").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                                }
                                Spacer()
                                Button { _ = saveDraft() } label: {
                                    Text("Add").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                                }
                                    .disabled(!hasDraft)
                                    .accessibilityIdentifier("thought.capture.add")
                            }.buttonStyle(.borderless)
                        } else {
                            Button {
                                composerVisible = true
                                Task { @MainActor in
                                    await Task.yield()
                                    textFocused = true
                                }
                            } label: {
                                Label("Add a thought", systemImage: "plus")
                                    .frame(minHeight: 44)
                            }.accessibilityIdentifier("thought.capture.new")
                        }
                        if let error { Text(error).foregroundStyle(.red) }
                    }.id("thought.composer")
                }
                .onChange(of: composerVisible) { _, visible in
                    if visible { withAnimation { proxy.scrollTo("thought.composer", anchor: .bottom) } }
                }
                .onChange(of: textFocused) { _, focused in
                    if focused { withAnimation { proxy.scrollTo("thought.composer", anchor: .bottom) } }
                }
                .onChange(of: error) { _, message in
                    if message != nil { withAnimation { proxy.scrollTo("thought.composer", anchor: .bottom) } }
                }
            }
            .appScreen()
            .navigationTitle(context.originSessionID == nil ? "New thoughts" : "Session thoughts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if !hasDraft || saveDraft() { dismiss() }
                    }.accessibilityIdentifier("thought.capture.done")
                }
            }
            .interactiveDismissDisabled(hasDraft)
            .sheet(item: $editing) { ThoughtEditor(store: store, thoughtID: $0.id) }
            .confirmationDialog("Discard this thought?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard thought", role: .destructive) { discardDraft() }
                Button("Keep editing", role: .cancel) { }
            }
            .task { textFocused = true }
        }
    }

    private func thoughtRow(_ thought: CapturedThought) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                if !store.setThoughtCompleted(id: thought.id, completed: thought.completedAt == nil) {
                    consumeError()
                }
            } label: {
                Image(systemName: thought.completedAt == nil ? "square" : "checkmark.square.fill")
                    .font(.title2).frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(thought.completedAt == nil ? "Mark thought done" : "Mark thought open")
            .accessibilityValue(thought.completedAt == nil ? "Open" : "Done")
            .accessibilityIdentifier("thought.check")
            Button { editing = thought } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(thought.text).strikethrough(thought.completedAt != nil).foregroundStyle(.primary)
                    if context.originSessionID == nil, let project = thought.projectID {
                        Text(store.projectName(project)).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
        }
    }

    private func saveDraft() -> Bool {
        let capture = ThoughtCaptureContext(
            projectID: context.originSessionID == nil ? projectID : context.projectID,
            originSessionID: context.originSessionID)
        guard let id = store.createThought(context: capture, text: draft) else {
            consumeError()
            return false
        }
        createdIDs.insert(id)
        draft = ""
        error = nil
        composerVisible = false
        textFocused = false
        return true
    }

    private func discardDraft() {
        draft = ""
        error = nil
        composerVisible = false
        textFocused = false
    }

    private func consumeError() {
        error = store.errorMessage ?? "Your changes could not be saved. Try again."
        store.errorMessage = nil
    }
}
