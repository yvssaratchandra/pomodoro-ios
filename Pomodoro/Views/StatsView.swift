import SwiftUI

struct StatsView: View {
    @Bindable var store: AppStore
    @State private var showAllHistory = false
    @State private var pendingDeletion: FocusSession?
    @State private var confirmingDeletion = false
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                List {
                    Section("Today · \(timeline.date.formatted(date: .abbreviated, time: .omitted))") {
                        GoalProgress(state: store.state, now: timeline.date)
                    }.listRowBackground(AppTheme.surface)
                    Section {
                        Picker("Session history", selection: $showAllHistory) {
                            Text("Today").tag(false)
                            Text("All history").tag(true)
                        }.pickerStyle(.segmented)
                    }.listRowBackground(AppTheme.surface)
                    Section("Focus sessions") {
                        if let active = store.state.activeTimer, active.kind == .focus {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.projectName(active.projectID)).font(.headline)
                                Text("\(active.startedAt.formatted(date: .omitted, time: .shortened)) · \(DurationText.work(active.elapsed(at: timeline.date)))")
                                Label("In progress", systemImage: "timer").foregroundStyle(.indigo)
                            }.accessibilityElement(children: .combine)
                        }
                        let sessions = showAllHistory
                            ? store.state.sessions.sorted { $0.startedAt > $1.startedAt }
                            : Statistics.sessionsToday(store.state, now: timeline.date)
                        ForEach(sessions) { session in
                            SessionRow(session: session, name: store.projectName(session.projectID),
                                day: showAllHistory ? nil : Statistics.today(timeline.date))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Delete", systemImage: "trash") { requestDeletion(session) }
                                        .tint(.red)
                                }
                                .contextMenu {
                                    Button("Delete Session", systemImage: "trash", role: .destructive) { requestDeletion(session) }
                                }
                                .accessibilityAction(named: "Delete Session") { requestDeletion(session) }
                        }
                        if sessions.isEmpty && store.state.activeTimer?.kind != .focus {
                            ContentUnavailableView("No Focus Yet", systemImage: "timer",
                                description: Text("Start a session in Focus. Completed and interrupted sessions will appear here."))
                        }
                    }.listRowBackground(AppTheme.surface)
                }
                .appScreen()
            }.navigationTitle("Stats")
            .alert("Delete this session?", isPresented: $confirmingDeletion) {
                Button("Delete Session", role: .destructive) {
                    if let session = pendingDeletion { store.deleteSession(session.id) }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                if let session = pendingDeletion {
                    Text("Delete \(DurationText.work(session.duration)) for \(store.projectName(session.projectID)) from \(session.startedAt.formatted(date: .abbreviated, time: .shortened))? This removes its time from all statistics and cannot be undone.")
                }
            }
        }
    }

    private func requestDeletion(_ session: FocusSession) {
        pendingDeletion = session
        confirmingDeletion = true
    }
}

struct SessionRow: View {
    let session: FocusSession
    let name: String
    var day: DateInterval? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline)
            Text("\(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(DurationText.work(session.duration))")
            Label(session.outcome == .completed ? "Completed" : "Interrupted",
                  systemImage: session.outcome == .completed ? "checkmark.circle" : "stop.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(session.outcome == .completed ? Color.green : Color.secondary)
            if let day, session.startedAt < day.start || session.endedAt > day.end {
                Text("Today: \(DurationText.work(Statistics.overlap(start: session.startedAt, end: session.endedAt, interval: day)))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session.\(session.outcome.rawValue)")
    }
}
