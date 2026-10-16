import SwiftUI

struct ThoughtEditor: View {
    let store: AppStore
    let context: ThoughtCaptureContext?
    let thoughtID: UUID?
    private let original: String
    private let originalProject: UUID?
    @State private var draft: String
    @State private var projectID: UUID?
    @State private var error: String?
    @State private var confirmingDiscard = false
    @FocusState private var textFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore, context: ThoughtCaptureContext? = nil, thoughtID: UUID? = nil) {
        self.store = store; self.context = context; self.thoughtID = thoughtID
        let thought = thoughtID.flatMap { id in store.state.thoughts.first { $0.id == id } }
        original = thought?.text ?? ""
        originalProject = thought?.projectID ?? context?.projectID
        _draft = State(initialValue: original)
        _projectID = State(initialValue: originalProject)
    }
    private var dirty: Bool { draft != original || projectID != originalProject }
    private var normalized: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Save this thought for later", text: $draft, axis: .vertical)
                        .lineLimit(4...12).focused($textFocused).accessibilityIdentifier("thought.text")
                    if draft.count >= 450 {
                        Text("\(draft.count) / 500").foregroundStyle(draft.count > 500 ? .red : .secondary)
                    }
                }
                if thoughtID == nil, context?.originSessionID == nil {
                    Picker("Project", selection: $projectID) {
                        Text("Unassigned").tag(Optional<UUID>.none)
                        ForEach(store.state.projects) { Text($0.name).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("thought.project")
                } else if let projectID {
                    LabeledContent("Project", value: store.projectName(projectID))
                }
                if let thoughtID, let thought = store.state.thoughts.first(where: { $0.id == thoughtID }) {
                    DisclosureGroup("Details") {
                        LabeledContent("Created", value: thought.createdAt.formatted(date: .abbreviated, time: .shortened))
                        if let completed = thought.completedAt {
                            LabeledContent("Completed", value: completed.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let origin = thought.originSessionID {
                            Text(store.state.sessions.contains(where: { $0.id == origin }) || store.state.activeTimer?.id == origin
                                 ? "Captured during focus" : "Captured during an earlier session")
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .appScreen().navigationTitle(thoughtID == nil ? "New thought" : "Edit thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { confirmingDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved: Bool
                        if let thoughtID { saved = store.editThought(id: thoughtID, text: draft) }
                        else {
                            let capture = ThoughtCaptureContext(projectID: projectID, originSessionID: context?.originSessionID)
                            saved = store.captureThought(context: capture, text: draft)
                        }
                        if saved { dismiss() } else { error = store.errorMessage; store.errorMessage = nil }
                    }.disabled(normalized.isEmpty || normalized.count > 500).accessibilityIdentifier("thought.save")
                }
            }
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) { }
            }
            .task { textFocused = true }
        }
    }
}

struct ThoughtsView: View {
    @Bindable var store: AppStore
    @Bindable var navigation: AppNavigation
    @State private var editing: CapturedThought?
    @State private var capture: ThoughtCaptureContext?
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var confirmingBulkDelete = false

    private var thoughts: [CapturedThought] {
        store.state.thoughts.filter {
            navigation.thoughtProjectFilter.includes($0.projectID)
                && (navigation.thoughtFilter == 0 || (navigation.thoughtFilter == 1 ? $0.completedAt == nil : $0.completedAt != nil))
                && (navigation.thoughtSearch.isEmpty || $0.text.localizedStandardContains(navigation.thoughtSearch))
        }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt }
    }
    private var filtered: Bool {
        navigation.thoughtProjectFilter != .all || navigation.thoughtFilter != 0 || !navigation.thoughtSearch.isEmpty
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Thoughts", selection: $navigation.thoughtFilter) {
                        Text("All").tag(0); Text("Open").tag(1); Text("Done").tag(2)
                    }.pickerStyle(.segmented)
                    Picker("Project", selection: $navigation.thoughtProjectFilter) {
                        Text("All projects").tag(ThoughtProjectFilter.all)
                        Text("Unassigned").tag(ThoughtProjectFilter.unassigned)
                        ForEach(store.state.projects) { Text($0.name).tag(ThoughtProjectFilter.project($0.id)) }
                    }.accessibilityIdentifier("thoughts.project")
                }
                ForEach(thoughts) { thought in
                    thoughtRow(thought)
                        .swipeActions {
                            if !selecting { Button("Delete", role: .destructive) { store.deleteThought(id: thought.id) } }
                        }
                        .contextMenu {
                            Button("Edit") { editing = thought }
                            Button("Delete", role: .destructive) { store.deleteThought(id: thought.id) }
                        }
                }
                if thoughts.isEmpty {
                    ContentUnavailableView {
                        Label(filtered ? "No matching thoughts" : "No thoughts yet", systemImage: "text.bubble")
                    } description: {
                        Text(filtered ? "Try another search or filter." : "Save a thought now or capture one while focusing.")
                    } actions: {
                        if filtered { Button("Clear filters") { clearFilters() } }
                        else { Button("Add thought") { createThought() } }
                    }
                }
            }
            .appScreen().navigationTitle("Thoughts")
            .searchable(text: $navigation.thoughtSearch, prompt: "Search thoughts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selecting ? "Done" : "Select") { selecting.toggle(); selection.removeAll() }
                        .disabled(store.state.thoughts.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New thought", systemImage: "plus") { createThought() }.accessibilityIdentifier("thoughts.new")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    HStack {
                        Menu("Mark") {
                            Button("Done") { completeSelection(true) }
                            Button("Open") { completeSelection(false) }
                        }.disabled(selection.isEmpty)
                        Spacer()
                        Text("\(selection.count) selected").font(.subheadline)
                        Spacer()
                        Button("Delete", role: .destructive) { confirmingBulkDelete = true }.disabled(selection.isEmpty)
                    }.padding().background(.regularMaterial)
                }
            }
            .sheet(item: $editing) { ThoughtEditor(store: store, thoughtID: $0.id) }
            .sheet(item: $capture) { ThoughtEditor(store: store, context: $0) }
            .confirmationDialog("Delete \(selection.count) thoughts?", isPresented: $confirmingBulkDelete, titleVisibility: .visible) {
                Button("Delete thoughts", role: .destructive) {
                    if store.deleteThoughts(ids: selection) { selection.removeAll(); selecting = false }
                }
                Button("Cancel", role: .cancel) { }
            }
            .onChange(of: thoughts.map(\.id)) { _, ids in selection.formIntersection(Set(ids)) }
            .onChange(of: store.state.projects.map(\.id)) { _, ids in
                if case .project(let id) = navigation.thoughtProjectFilter, !ids.contains(id) { navigation.thoughtProjectFilter = .all }
            }
        }
    }

    private func thoughtRow(_ thought: CapturedThought) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                if selecting {
                    if selection.contains(thought.id) { selection.remove(thought.id) } else { selection.insert(thought.id) }
                } else { _ = store.setThoughtCompleted(id: thought.id, completed: thought.completedAt == nil) }
            } label: {
                Image(systemName: selecting
                      ? (selection.contains(thought.id) ? "checkmark.circle.fill" : "circle")
                      : (thought.completedAt == nil ? "square" : "checkmark.square.fill"))
                    .font(.title2).frame(width: 44, height: 44)
            }.buttonStyle(.borderless)
                .accessibilityLabel(selecting ? "Select thought" : (thought.completedAt == nil ? "Mark thought done" : "Mark thought open"))
                .accessibilityValue(selecting ? (selection.contains(thought.id) ? "Selected" : "Not selected") : (thought.completedAt == nil ? "Open" : "Done"))
                .accessibilityIdentifier("thought.check")
            Button {
                if selecting {
                    if selection.contains(thought.id) { selection.remove(thought.id) } else { selection.insert(thought.id) }
                } else { editing = thought }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(thought.text).strikethrough(thought.completedAt != nil).foregroundStyle(.primary)
                    if navigation.thoughtProjectFilter == .all, let project = thought.projectID {
                        Text(store.projectName(project)).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain)
        }
    }
    private func createThought() {
        let project: UUID?
        if case .project(let id) = navigation.thoughtProjectFilter { project = id } else { project = nil }
        capture = ThoughtCaptureContext(projectID: project, originSessionID: nil)
    }
    private func clearFilters() {
        navigation.thoughtFilter = 0; navigation.thoughtProjectFilter = .all; navigation.thoughtSearch = ""
    }
    private func completeSelection(_ completed: Bool) {
        if store.setThoughtsCompleted(ids: selection, completed: completed) { selection.removeAll(); selecting = false }
    }
}
