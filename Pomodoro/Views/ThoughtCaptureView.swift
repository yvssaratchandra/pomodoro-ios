import SwiftUI

struct ThoughtCaptureView: View {
    let store: AppStore
    let context: ThoughtCaptureContext
    @State private var draft = ""
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

    private var normalized: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasDraft: Bool { !normalized.isEmpty }
    private var canAdd: Bool { hasDraft && normalized.count <= 500 }
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
                List {
                    ForEach(thoughts) { thought in
                        thoughtRow(thought).id(thought.id)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer {
                        guard let id = saveDraft() else { return }
                        Task { @MainActor in
                            await Task.yield()
                            textFocused = true
                            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
            }
            .appScreen()
            .navigationTitle(context.originSessionID == nil ? "New thoughts" : "Session thoughts")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if hasDraft { confirmingDiscard = true } else { dismiss() }
                    }.accessibilityIdentifier("thought.capture.done")
                }
            }
            .interactiveDismissDisabled(hasDraft)
            .sheet(item: $editing, onDismiss: restoreFocus) {
                ThoughtEditor(store: store, thoughtID: $0.id)
            }
            .confirmationDialog("Discard this draft?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) {
                    draft = ""
                    dismiss()
                }
                Button("Keep editing", role: .cancel, action: restoreFocus)
            }
            .task { textFocused = true }
        }
    }

    private func composer(onAdd: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if context.originSessionID == nil {
                Menu {
                    Picker("Project", selection: $projectID) {
                        Text("Unassigned").tag(Optional<UUID>.none)
                        ForEach(store.state.projects) { Text($0.name).tag(Optional($0.id)) }
                    }
                } label: {
                    Label(projectID.map { store.projectName($0) } ?? "Unassigned", systemImage: "folder")
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Project")
                .accessibilityValue(projectID.map { store.projectName($0) } ?? "Unassigned")
                .accessibilityIdentifier("thought.project")
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Add a thought…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($textFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("thought.text")
                Button(action: onAdd) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!canAdd)
                .accessibilityLabel("Add thought")
                .accessibilityIdentifier("thought.capture.add")
            }
            if normalized.count >= 450 {
                Text("\(normalized.count) / 500")
                    .font(.caption)
                    .foregroundStyle(normalized.count > 500 ? .red : .secondary)
            }
            if normalized.count > 500 {
                Text("Thoughts can contain up to 500 characters.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
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
            Button {
                textFocused = false
                editing = thought
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(thought.text).strikethrough(thought.completedAt != nil).foregroundStyle(.primary)
                    if context.originSessionID == nil, let project = thought.projectID {
                        Text(store.projectName(project)).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
        }
    }

    private func saveDraft() -> UUID? {
        guard canAdd else { return nil }
        let capture = ThoughtCaptureContext(
            projectID: context.originSessionID == nil ? projectID : context.projectID,
            originSessionID: context.originSessionID)
        guard let id = store.createThought(context: capture, text: draft) else {
            consumeError()
            restoreFocus()
            return nil
        }
        createdIDs.insert(id)
        draft = ""
        error = nil
        textFocused = true
        return id
    }

    private func restoreFocus() {
        Task { @MainActor in
            await Task.yield()
            textFocused = true
        }
    }

    private func consumeError() {
        error = store.errorMessage ?? "Your changes could not be saved. Try again."
        store.errorMessage = nil
    }
}
