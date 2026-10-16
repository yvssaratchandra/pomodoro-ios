import SwiftUI

struct FocusView: View {
    @Bindable var store: AppStore
    @State private var selectedID: UUID?
    @State private var durationProject: Project?
    @State private var showingCreate = false
    @State private var confirmingEnd = false

    private var selected: Project? { store.state.projects.first { $0.id == selectedID } }
    private var minutes: Int { selected?.preferredFocusMinutes ?? store.state.settings.defaultFocusMinutes }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    timer
                    sessionAction
                    sessionSetup
                        .focusCard()
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Today's goal · All projects", systemImage: "target")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                GoalProgress(state: store.state, now: timeline.date)
                            }.focusCard()
                            if let selected {
                                projectMetrics(selected, now: timeline.date).focusCard()
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCreate) { ProjectEditor(store: store, project: nil) }
            .sheet(item: $durationProject) { project in
                FocusDurationSheet(store: store, project: project)
            }
            .confirmationDialog("End this focus session?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End and Save Work", role: .destructive) { store.endTimer() }
            } message: { Text("Elapsed focus time will be saved as an interrupted session.") }
            .onAppear { repairSelection() }
            .onChange(of: store.state.projects) { _, _ in repairSelection() }
        }
    }

    @ViewBuilder private var timer: some View {
        if let active = store.state.activeTimer {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                TimerFace(seconds: max(0, active.deadline.timeIntervalSince(timeline.date)),
                    fraction: 1 - active.elapsed(at: timeline.date) / Double(active.plannedSeconds),
                    title: active.kind.title, project: store.projectName(active.projectID),
                    isBreak: active.kind != .focus, isRunning: true)
            }
        } else if let offer = store.state.breakOffer {
            TimerFace(seconds: Double(offer.minutes * 60), fraction: 1,
                title: "Ready for a \(offer.kind.title.lowercased())",
                project: store.projectName(offer.projectID), isBreak: true, isRunning: false)
        } else {
            TimerFace(seconds: Double(minutes * 60), fraction: 1, title: "Ready to focus",
                project: selected?.name ?? "Make time for what matters", isBreak: false, isRunning: false)
        }
    }

    @ViewBuilder private var sessionAction: some View {
        if let active = store.state.activeTimer {
            Button(role: .destructive) {
                if active.kind == .focus { confirmingEnd = true } else { store.endTimer() }
            } label: {
                Label(active.kind == .focus ? "End Focus" : "End Break", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.bordered).controlSize(.large)
            .accessibilityIdentifier("timer.end")
        } else if let offer = store.state.breakOffer {
            VStack(spacing: 8) {
                Button { store.startBreak() } label: {
                    Label("Start \(offer.kind.title)", systemImage: "cup.and.saucer.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(.teal)
                Button("Skip Break") { store.update { $0.breakOffer = nil } }
                    .padding(8)
            }
        } else if store.state.projects.isEmpty {
            Button { showingCreate = true } label: {
                Label("Create Project", systemImage: "plus")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            Button {
                if let selectedID { store.startFocus(projectID: selectedID, minutes: minutes) }
            } label: {
                Label("Start Focus", systemImage: "play.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(selected?.status != .ongoing)
            .accessibilityIdentifier("focus.start")
        }
    }

    private var sessionSetup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(store.state.activeTimer == nil ? "Focus session" : "Next focus session", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if store.state.projects.isEmpty {
                Text("Create a project to start focusing.").foregroundStyle(.secondary)
            } else {
                Picker(selection: $selectedID) {
                    Text("Choose a project").tag(Optional<UUID>.none)
                    ForEach(store.state.projects) { project in
                        Text(project.name + (project.status == .ongoing ? "" : " · \(project.status.title)"))
                            .tag(Optional(project.id))
                    }
                } label: { Label("Project", systemImage: "folder") }
                .pickerStyle(.menu)
                .accessibilityIdentifier("focus.project")
                Divider()
                Button { durationProject = selected } label: {
                    HStack {
                        Label("Duration", systemImage: "clock")
                        Spacer()
                        Text("\(minutes) min").monospacedDigit().fontWeight(.semibold)
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .disabled(selected == nil)
                .accessibilityIdentifier("focus.duration")
                .accessibilityLabel("Focus duration")
                .accessibilityValue("\(minutes) min")
                if let selected, selected.status != .ongoing {
                    Text("Reopen this project in Projects to start a session.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func projectMetrics(_ project: Project, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(project.name, systemImage: "folder.fill").font(.headline)
            LabeledContent("Today") {
                Text(DurationText.work(Statistics.total(store.state, projectID: project.id,
                    interval: Statistics.today(now), now: now)))
                    .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            LabeledContent("Daily average · 7 days") {
                Text(DurationText.work(Statistics.dailyAverage(store.state, projectID: project.id, now: now)))
                    .font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            Text("Includes today and the previous six days, including days with no focus time.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func repairSelection() {
        guard selected == nil else { return }
        selectedID = store.state.projects.first(where: { $0.status == .ongoing })?.id ?? store.state.projects.first?.id
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
                Text("Remembered for this project. Applies to your next focus session.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize = 80.0

    private var tint: Color { isBreak ? .teal : .indigo }
    private var digits: some View {
        Text(DurationText.countdown(seconds))
            .font(.system(size: digitSize, weight: .semibold, design: .rounded).monospacedDigit())
            .minimumScaleFactor(0.5).lineLimit(1)
            .foregroundStyle(.primary)
            .contentTransition(.numericText(countsDown: true))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: Int(ceil(seconds)))
            .accessibilityLabel(isRunning ? "Time remaining" : "Session duration")
            .accessibilityValue(DurationText.work(seconds))
            .accessibilityIdentifier(isRunning ? "timer.countdown" : "timer.preview")
    }

    var body: some View {
        VStack(spacing: 14) {
            Label(title, systemImage: isBreak ? "cup.and.saucer.fill" : "timer")
                .font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(tint.opacity(0.1), in: Capsule())
            if dynamicTypeSize.isAccessibilitySize {
                digits.frame(maxWidth: .infinity)
                ProgressView(value: min(1, max(0, fraction))).tint(tint).accessibilityHidden(true)
            } else {
                ZStack {
                    Circle().fill(tint.opacity(0.04))
                    Circle().stroke(tint.opacity(0.12), lineWidth: 8)
                    Circle().trim(from: 0, to: min(1, max(0, fraction)))
                        .stroke(tint.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    digits.padding(.horizontal, 16)
                }
                .frame(maxWidth: 280)
                .aspectRatio(1, contentMode: .fit)
                .padding(6)
            }
            Text(project).font(.headline).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

private extension View {
    func focusCard() -> some View {
        self.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}

struct GoalProgress: View {
    let state: AppSnapshot
    let now: Date
    var body: some View {
        let worked = Statistics.total(state, interval: Statistics.today(now), now: now)
        let goal = Double(state.settings.dailyGoalMinutes * 60)
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(DurationText.work(worked)).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                    Text("of \(DurationText.work(goal))").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text(DurationText.work(worked)).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                    Text("of \(DurationText.work(goal))").foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(worked, goal), total: goal)
                .tint(worked >= goal ? .green : .indigo)
                .accessibilityLabel("Daily goal progress")
                .accessibilityValue("\(Int(worked / goal * 100)) percent")
            if worked >= goal {
                Label("Daily goal reached", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
            }
        }.padding(.vertical, 4)
    }
}
