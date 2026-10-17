import SwiftUI

private enum FocusScreenState {
    case empty
    case ready(Project)
    case focusing(ActiveTimer)
    case breakReady(BreakOffer)
    case onBreak(ActiveTimer)
}

private struct BreakDurationRequest: Identifiable {
    let id = UUID()
    let offer: BreakOffer
}

struct FocusView: View {
    @Bindable var store: AppStore
    @Bindable var navigation: AppNavigation
    @ObservedObject var dimFocus: DimFocusCoordinator
    @ObservedObject var presentation: AppPresentationContext
    @State private var durationProject: Project?
    @State private var breakDuration: BreakDurationRequest?
    @State private var draftNoteProject: Project?
    @State private var confirmingEnd = false
    @State private var noteTimer: ActiveTimer?
    @State private var breadcrumbSession: FocusSession?

    private var selected: Project? { store.state.projects.first { $0.id == navigation.selectedProjectID && $0.status == .ongoing } }
    private var activeProjects: [Project] { store.state.projects.filter { $0.status == .ongoing } }
    private var minutes: Int { selected?.preferredFocusMinutes ?? store.state.settings.defaultFocusMinutes }
    private var screenState: FocusScreenState {
        if let active = store.state.activeTimer {
            return active.kind == .focus ? .focusing(active) : .onBreak(active)
        }
        if let offer = store.state.breakOffer { return .breakReady(offer) }
        if let selected { return .ready(selected) }
        return .empty
    }

    private var hasEditor: Bool {
        durationProject != nil || breakDuration != nil || draftNoteProject != nil || noteTimer != nil || breadcrumbSession != nil
    }

    private func editorDismissed() {
        dimFocus.setBlocked("focus-editor", hasEditor)
        navigation.setCapturePresentationBlocked(hasEditor, owner: "focus-editor")
    }

    var body: some View {
        NavigationStack(path: $navigation.focusPath) {
            ScrollView {
                VStack(spacing: 18) {
                    switch screenState {
                    case .empty: emptyProjects
                    case .ready(let project): ready(project)
                    case .focusing(let timer), .onBreak(let timer): running(timer)
                    case .breakReady(let offer): breakReady(offer)
                    }
                }
                .padding(20)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .appScreen()
            .navigationTitle(store.state.activeTimer?.kind == .focus ? "Focusing" : store.state.activeTimer != nil ? "Break" : "Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if store.state.activeTimer?.kind == .focus {
                        Button {
                            if dimFocus.state.isEnabled { dimFocus.disable() }
                            else { dimFocus.enable() }
                        } label: {
                            Image(systemName: "circle.lefthalf.filled")
                        }
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(dimFocus.state.isEnabled ? Color.indigo : Color.secondary)
                        .accessibilityLabel(dimFocus.state.isEnabled ? "Disable Dim Focus" : "Enable Dim Focus")
                        .accessibilityValue(dimFocus.state.isEnabled ? "On" : "Off")
                        .accessibilityIdentifier("dimFocusToggle")
                    }
                    Button("Settings", systemImage: "gearshape") { navigation.showSettings() }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18, weight: .regular))
                        .frame(width: 44, height: 44)
                        .accessibilityIdentifier("focus.settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    FocusMenuButton(actions: focusMenuActions) { showing in
                        dimFocus.setBlocked("focus-menu", showing)
                        navigation.setCapturePresentationBlocked(showing, owner: "focus-menu")
                    }
                    .frame(width: 44, height: 44)
                }
            }
            .navigationDestination(for: FocusDestination.self) { destination in
                switch destination {
                case .projects: ProjectsView(store: store, navigation: navigation)
                case .settings: SettingsView(store: store)
                }
            }
            .sheet(item: $durationProject, onDismiss: editorDismissed) { FocusDurationSheet(store: store, project: $0) }
            .sheet(item: $breakDuration, onDismiss: editorDismissed) { request in
                BreakDurationSheet(store: store, offer: request.offer)
            }
            .sheet(item: $draftNoteProject, onDismiss: editorDismissed) { project in
                DraftSessionNoteEditor(text: Binding(
                    get: { navigation.sessionNoteDrafts[project.id] ?? "" },
                    set: { navigation.sessionNoteDrafts[project.id] = $0 }))
            }
            .sheet(item: $noteTimer, onDismiss: editorDismissed) { IntentionEditor(store: store, sessionID: $0.id, active: true) }
            .sheet(item: $breadcrumbSession, onDismiss: editorDismissed) { BreadcrumbEditor(store: store, sessionID: $0.id, promote: true) }
            .alert("End focus?", isPresented: $confirmingEnd) {
                Button("Save Session") { store.endTimer() }
                Button("Discard Session", role: .destructive) {
                    if let timer = store.state.activeTimer { store.discardFocus(timerID: timer.id) }
                }
                Button("Keep Focusing", role: .cancel) { }
            } message: { Text("Save the time you’ve focused, or discard this session.") }
            .background {
                FocusInteractionObserver(
                    enabled: dimFocus.state.isEnabled && !dimFocus.isDimmed && presentation.isActive && navigation.selectedTab == .focus && navigation.focusPath.isEmpty,
                    onBegin: dimFocus.beginInteraction, onEnd: dimFocus.endInteraction,
                    canObserve: { !presentation.hasPresentedContent })
            }
            .onChange(of: hasEditor) { _, showing in
                dimFocus.setBlocked("focus-editor", showing)
                if showing { navigation.setCapturePresentationBlocked(true, owner: "focus-editor") }
            }
            .onChange(of: confirmingEnd) { _, showing in
                dimFocus.setBlocked("focus-end-confirmation", showing)
                navigation.setCapturePresentationBlocked(showing, owner: "focus-end-confirmation")
            }
            .onChange(of: store.state.activeTimer?.id) { _, _ in confirmingEnd = false }
            .onChange(of: navigation.focusRequestID) { _, _ in
                durationProject = nil
                breakDuration = nil
                draftNoteProject = nil
                confirmingEnd = false
            }
            .onAppear { repairSelection() }
            .onChange(of: store.state.projects) { _, _ in repairSelection() }
        }
    }

    private var focusMenuActions: [FocusMenuAction] {
        var actions = [FocusMenuAction(title: "Manage projects", systemImage: "folder", identifier: "focus.projects") {
            navigation.showProjects()
        }]
        if case .ready(let project) = screenState {
            actions.append(FocusMenuAction(title: "Plan this session", systemImage: "square.and.pencil", identifier: "focus.intention") {
                draftNoteProject = project
            })
        }
        if case .focusing(let timer) = screenState {
            actions.append(FocusMenuAction(title: timer.intention == nil ? "Plan this session" : "Edit this session",
                                          systemImage: "square.and.pencil", identifier: "focus.intention.edit") { noteTimer = timer })
        }
        return actions
    }

    private var emptyProjects: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(activeProjects.isEmpty && !store.state.projects.isEmpty ? "No Active Projects" : "Start Focusing",
                systemImage: "timer", description: Text(activeProjects.isEmpty && !store.state.projects.isEmpty
                    ? "Choose an active project or create a new one." : "Create a project to begin."))
            Button("Create Project", systemImage: "plus") { navigation.showingProjectCreation = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            if !store.state.projects.isEmpty {
                Button("Manage projects") { navigation.showProjects() }
            }
        }
    }

    private func ready(_ project: Project) -> some View {
        VStack(spacing: 18) {
            Menu {
                ForEach(activeProjects) { option in
                    Button(option.name) { navigation.selectedProjectID = option.id }
                }
                Divider()
                Button("New project", systemImage: "plus") { navigation.showingProjectCreation = true }
                Button("Manage projects", systemImage: "folder") { navigation.showProjects() }
            } label: {
                HStack {
                    Label(project.name, systemImage: "folder")
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("focus.project")
            TimerFace(seconds: Double(minutes * 60), fraction: 1, title: "", project: "", isBreak: false, isRunning: false)
            Button { durationProject = project } label: {
                Label("\(minutes) min", systemImage: "clock")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("focus.duration")
            .accessibilityLabel("Focus duration")
            .accessibilityValue("\(minutes) min")
            Button {
                if store.startFocus(projectID: project.id, minutes: minutes, intention: navigation.sessionNoteDrafts[project.id]) {
                    navigation.sessionNoteDrafts[project.id] = nil
                }
            } label: {
                Label("Start Focus", systemImage: "play.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .accessibilityIdentifier("focus.start")
            let taskCount = SessionPlanText.items(from: navigation.sessionNoteDrafts[project.id]).count
            if taskCount > 0 {
                SessionPlanSummaryRow(taskCount: taskCount) { draftNoteProject = project }
                    .accessibilityIdentifier("focus.intention")
            }
            if project.breadcrumb != nil {
                BreadcrumbCard(store: store, project: project,
                               useAsIntention: { navigation.sessionNoteDrafts[project.id] = $0 })
            } else if let id = store.lastFinishedSessionID,
                      let session = store.state.sessions.first(where: { $0.id == id && $0.projectID == project.id && $0.nextStep == nil }) {
                Button("Plan next session") { breadcrumbSession = session }
                    .accessibilityIdentifier("focus.nextStep")
            }
        }
    }

    private func running(_ active: ActiveTimer) -> some View {
        VStack(spacing: 18) {
            Text(store.projectName(active.projectID)).font(.headline).multilineTextAlignment(.center)
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                TimerFace(seconds: max(0, active.deadline.timeIntervalSince(timeline.date)),
                    fraction: 1 - active.elapsed(at: timeline.date) / Double(active.plannedSeconds),
                    title: "", project: "",
                    isBreak: active.kind != .focus, isRunning: true)
            }
            if active.kind == .focus {
                Button(role: .destructive) { confirmingEnd = true } label: {
                    Label("End Focus", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .accessibilityIdentifier("timer.end")
                let taskCount = SessionPlanText.items(from: active.intention).count
                if taskCount > 0 {
                    SessionPlanSummaryRow(taskCount: taskCount) { noteTimer = active }
                        .accessibilityIdentifier("focus.intention.edit")
                }
                Button("Add a thought", systemImage: "text.bubble") {
                    navigation.requestThoughtCapture(context: ThoughtCaptureContext(projectID: active.projectID, originSessionID: active.id))
                }.accessibilityIdentifier("focus.captureThought")
            } else {
                Button("End Break", systemImage: "stop.fill") { store.endTimer() }
                    .buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("timer.end")
                Button("Plan next session", systemImage: "square.and.pencil") {
                    navigation.requestNextSessionPlan(projectID: active.projectID)
                }
                .accessibilityIdentifier("focus.nextStep")
                Button("Review thoughts") { navigation.showThoughts(projectID: active.projectID) }
            }
        }
    }

    private func breakReady(_ offer: BreakOffer) -> some View {
        VStack(spacing: 18) {
            Text("Focus saved").font(.headline)
            TimerFace(seconds: Double(offer.minutes * 60), fraction: 1, title: "", project: store.projectName(offer.projectID), isBreak: true, isRunning: false)
            Button { breakDuration = BreakDurationRequest(offer: offer) } label: {
                Label("\(offer.minutes) min", systemImage: "clock").frame(minHeight: 44)
            }
            .accessibilityIdentifier("break.duration")
            .accessibilityLabel("Break duration")
            .accessibilityValue("\(offer.minutes) min")
            Button { store.startBreak() } label: {
                Label("Start Break", systemImage: "cup.and.saucer.fill")
                    .foregroundStyle(AppTheme.breakButtonForeground)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).controlSize(.large).tint(AppTheme.breakAccent)
                .accessibilityIdentifier("break.start")
            Button("Skip Break") { store.update { $0.breakOffer = nil } }
            Button("Plan next session", systemImage: "square.and.pencil") {
                navigation.requestNextSessionPlan(projectID: offer.projectID)
            }
            .accessibilityIdentifier("focus.nextStep")
        }
    }

    private func repairSelection() {
        if selected == nil { navigation.selectedProjectID = activeProjects.first?.id }
    }
}

private struct SessionPlanSummaryRow: View {
    let taskCount: Int
    let action: () -> Void

    private var taskSummary: String { "\(taskCount) \(taskCount == 1 ? "task" : "tasks")" }

    var body: some View {
        Button(action: action) {
            HStack {
                Text("Session plan · \(taskSummary)")
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open session plan")
        .accessibilityValue(taskSummary)
    }
}

private struct FocusDurationSheet: View {
    let store: AppStore
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var draft: Int
    @State private var saveError: String?

    init(store: AppStore, project: Project) {
        self.store = store
        self.project = project
        _draft = State(initialValue: project.preferredFocusMinutes)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(project.name).font(.headline)
                Picker("Focus duration", selection: $draft) {
                    ForEach(10...60, id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.wheel)
                .accessibilityIdentifier("focus.duration.wheel")
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appScreen()
            .navigationTitle("Focus duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("focus.duration.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if store.rememberFocusDuration(projectID: project.id, minutes: draft) {
                            dismiss()
                        } else {
                            saveError = store.errorMessage
                            store.errorMessage = nil
                        }
                    }.accessibilityIdentifier("focus.duration.done")
                }
            }
            .alert("Unable to Save Duration", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct TimerFace: View {
    let seconds: TimeInterval
    let fraction: Double
    let title: String
    let project: String
    let isBreak: Bool
    let isRunning: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { isBreak ? AppTheme.breakAccent : .indigo }
    private var digits: some View {
        Text(DurationText.countdown(seconds))
            .font(dynamicTypeSize.isAccessibilitySize
                ? .system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit()
                : .system(size: 58, weight: .semibold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .foregroundStyle(.primary)
            .contentTransition(.numericText(countsDown: true))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: Int(ceil(seconds)))
            .accessibilityLabel(isRunning ? "Time remaining" : "Session duration")
            .accessibilityValue(DurationText.work(seconds))
            .accessibilityIdentifier(isRunning ? "timer.countdown" : "timer.preview")
    }

    var body: some View {
        VStack(spacing: 10) {
            if !title.isEmpty {
                Label(title, systemImage: isBreak ? "cup.and.saucer.fill" : "timer")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            }
            if dynamicTypeSize.isAccessibilitySize {
                digits.frame(maxWidth: .infinity)
                ProgressView(value: min(1, max(0, fraction))).tint(tint).accessibilityHidden(true)
            } else {
                ZStack {
                    Circle().fill(colorScheme == .dark ? Color.black : tint.opacity(0.04))
                    Circle().stroke(tint.opacity(0.12), lineWidth: 8)
                    Circle().trim(from: 0, to: min(1, max(0, fraction)))
                        .stroke(tint.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    digits.padding(.horizontal, 16)
                }
                .frame(maxWidth: 200)
                .aspectRatio(1, contentMode: .fit)
                .padding(6)
            }
            if !project.isEmpty { Text(project).font(.headline).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

struct GoalProgress: View {
    let state: AppSnapshot
    let now: Date
    var body: some View {
        let worked = Statistics.total(state, interval: Statistics.today(now), now: now)
        let target = GoalEngine.dailyTarget(on: now, plan: state.goalPlan)
        let goal = Double((target ?? 0) * 60)
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(DurationText.summary(worked)).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                    Text(goal > 0 ? "of \(DurationText.summary(goal))" : "focused").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text(DurationText.summary(worked)).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                    Text(goal > 0 ? "of \(DurationText.summary(goal))" : "focused").foregroundStyle(.secondary)
                }
            }
            if goal > 0 {
                ProgressView(value: min(worked, goal), total: goal).tint(worked >= goal ? .green : .indigo)
                    .accessibilityLabel("Daily goal progress")
                    .accessibilityValue("\(Int(worked / goal * 100)) percent")
                if worked >= goal { Label("Daily goal reached", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            } else {
                Text(target == 0 ? "Rest day" : "No recorded goal").foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
