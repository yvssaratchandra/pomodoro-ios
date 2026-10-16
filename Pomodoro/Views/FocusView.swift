import SwiftUI

struct FocusView: View {
    @Bindable var store: AppStore
    @State private var selectedID: UUID?
    @State private var minutes = 25
    @State private var showingCreate = false
    @State private var confirmingEnd = false

    private var selected: Project? { store.state.projects.first { $0.id == selectedID } }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Form {
                    Section("Today's goal · All projects") {
                        GoalProgress(state: store.state, now: timeline.date)
                    }
                    Section("Project") {
                        if store.state.projects.isEmpty {
                            Text("Create a project to start focusing.").foregroundStyle(.secondary)
                            Button("Create Project") { showingCreate = true }
                        } else {
                            Picker("Selected project", selection: $selectedID) {
                                Text("Choose a project").tag(Optional<UUID>.none)
                                ForEach(store.state.projects) { project in
                                    Text(project.name + (project.status == .ongoing ? "" : " · \(project.status.title)"))
                                        .tag(Optional(project.id))
                                }
                            }
                            .accessibilityIdentifier("focus.project")
                        }
                    }
                    if let timer = store.state.activeTimer {
                        Section(timer.kind.title) {
                            Text(store.projectName(timer.projectID)).font(.headline)
                            Text(DurationText.countdown(timer.deadline.timeIntervalSince(timeline.date)))
                                .font(.system(.largeTitle, design: .rounded).monospacedDigit())
                                .frame(maxWidth: .infinity).padding(.vertical)
                                .accessibilityLabel("Time remaining")
                                .accessibilityValue(DurationText.work(max(0, timer.deadline.timeIntervalSince(timeline.date))))
                                .accessibilityIdentifier("timer.countdown")
                            Button(timer.kind == .focus ? "End Focus" : "End Break", role: .destructive) {
                                if timer.kind == .focus { confirmingEnd = true } else { store.endTimer() }
                            }.accessibilityIdentifier("timer.end")
                        }
                    } else if let offer = store.state.breakOffer {
                        Section("Ready for a break") {
                            LabeledContent(offer.kind.title, value: "\(offer.minutes) min")
                            Text("After focusing on \(store.projectName(offer.projectID))").foregroundStyle(.secondary)
                            Button("Start \(offer.kind.title)") { store.startBreak() }.buttonStyle(.borderedProminent)
                            Button("Skip Break") { store.update { $0.breakOffer = nil } }
                        }
                    }
                    Section(store.state.activeTimer == nil ? "Focus session" : "Next focus session") {
                        Picker("Duration", selection: $minutes) {
                            ForEach(10...60, id: \.self) { Text("\($0) min").tag($0) }
                        }
                        if let selected, selected.status != .ongoing {
                            Text("Reopen this project in Projects to start a session.").foregroundStyle(.secondary)
                        }
                        if store.state.activeTimer == nil {
                            Button("Start Focus") {
                                if let selectedID { store.startFocus(projectID: selectedID, minutes: minutes) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selected?.status != .ongoing)
                            .accessibilityIdentifier("focus.start")
                        }
                    }
                    if let selected {
                        Section(selected.name) {
                            LabeledContent("Today", value: DurationText.work(Statistics.total(store.state,
                                projectID: selected.id, interval: Statistics.today(timeline.date), now: timeline.date)))
                            LabeledContent("Daily average · 7 days", value: DurationText.work(Statistics.dailyAverage(
                                store.state, projectID: selected.id, now: timeline.date)))
                            Text("Includes today and the previous six days, including days with no focus time.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Focus")
            .sheet(isPresented: $showingCreate) { ProjectEditor(store: store, project: nil) }
            .confirmationDialog("End this focus session?", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("End and Save Work", role: .destructive) { store.endTimer() }
            } message: { Text("Elapsed focus time will be saved as an interrupted session.") }
            .onAppear { repairSelection() }
            .onChange(of: store.state.projects) { _, _ in repairSelection() }
            .onChange(of: selectedID) { _, _ in minutes = selected?.focusMinutes ?? 25 }
        }
    }

    private func repairSelection() {
        if selected == nil {
            selectedID = store.state.projects.first(where: { $0.status == .ongoing })?.id ?? store.state.projects.first?.id
        }
        minutes = selected?.focusMinutes ?? store.state.settings.defaultFocusMinutes
    }
}

struct GoalProgress: View {
    let state: AppSnapshot
    let now: Date
    var body: some View {
        let worked = Statistics.total(state, interval: Statistics.today(now), now: now)
        let goal = Double(state.settings.dailyGoalMinutes * 60)
        VStack(alignment: .leading, spacing: 8) {
            Text("\(DurationText.work(worked)) of \(DurationText.work(goal))").font(.headline)
            ProgressView(value: min(worked, goal), total: goal)
                .accessibilityLabel("Daily goal progress")
                .accessibilityValue("\(Int(worked / goal * 100)) percent")
            if worked >= goal { Label("Daily goal reached", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        }.padding(.vertical, 4)
    }
}
