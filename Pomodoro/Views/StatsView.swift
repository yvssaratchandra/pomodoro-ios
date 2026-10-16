import SwiftUI
import Charts

private enum HistoryRange: String, CaseIterable, Identifiable {
    case today = "Today", all = "All history", week = "Week", month = "Month"
    var id: String { rawValue }
}

struct StatsView: View {
    @Bindable var store: AppStore
    @State private var range: HistoryRange = .today
    @State private var anchor = Date()
    @State private var projectID: UUID?
    @State private var selectedDay: Date?
    @State private var pendingDeletion: FocusSession?
    @State private var confirmingDeletion = false
    private var period: FocusPeriod { range == .week ? .week : .month }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let now = timeline.date
                List {
                    Section("Consistency") { ConsistencyView(state: store.state, now: now) }
                    Section {
                        Picker("Session history", selection: $range) {
                            ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Picker("Project", selection: $projectID) {
                            Text("All projects").tag(Optional<UUID>.none)
                            ForEach(store.state.projects) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    if range == .week || range == .month {
                        periodContent(now: now)
                    } else {
                        Section("Today's goal · All projects") { GoalProgress(state: store.state, now: now) }
                        Section("Focus sessions") {
                            if let active = store.state.activeTimer, active.kind == .focus, projectID == nil || active.projectID == projectID {
                                VStack(alignment: .leading) {
                                    Text(store.projectName(active.projectID)).font(.headline)
                                    Text("\(DurationText.work(active.elapsed(at: now))) · In progress")
                                }
                            }
                            let sessions = savedSessions(day: range == .today ? Statistics.today(now) : nil)
                            sessionRows(sessions, day: range == .today ? Statistics.today(now) : nil)
                            if sessions.isEmpty && store.state.activeTimer?.kind != .focus {
                                ContentUnavailableView("No Focus Yet", systemImage: "timer", description: Text("Start a session in Focus."))
                            }
                        }
                    }
                }
                .listRowBackground(AppTheme.surface)
                .appScreen()
            }
            .navigationTitle("Stats")
            .onChange(of: range) { _, _ in anchor = Date() }
            .sheet(isPresented: Binding(get: { selectedDay != nil }, set: { if !$0 { selectedDay = nil } })) {
                if let selectedDay {
                    NavigationStack {
                        List { sessionRows(savedSessions(day: Statistics.today(selectedDay)), day: Statistics.today(selectedDay)) }
                            .appScreen().navigationTitle(selectedDay.formatted(date: .abbreviated, time: .omitted))
                            .toolbar { Button("Done") { self.selectedDay = nil } }
                            .safeAreaInset(edge: .bottom) { UndoBanner(store: store) }
                    }
                }
            }
            .alert("Delete this session?", isPresented: $confirmingDeletion) {
                Button("Delete Session", role: .destructive) {
                    if let pendingDeletion { store.deleteSession(pendingDeletion.id) }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: { Text("This removes the session's time from all statistics. Undo is available briefly after deletion.") }
        }
    }

    @ViewBuilder private func periodContent(now: Date) -> some View {
        let interval = Statistics.interval(for: period, containing: anchor)
        let summary = Statistics.periodSummary(store.state, interval: interval, projectID: projectID, now: now)
        let comparison = Statistics.periodComparison(store.state, period: period, interval: interval, projectID: projectID, now: now)
        Section {
            HStack {
                Button("Previous", systemImage: "chevron.left") { move(-1) }.labelStyle(.iconOnly)
                Spacer()
                Text("\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))").font(.subheadline)
                Spacer()
                Button("Next", systemImage: "chevron.right") { move(1) }.labelStyle(.iconOnly).disabled(interval.end > now)
            }
            LabeledContent("Total focus", value: DurationText.work(summary.totalSeconds))
            LabeledContent("Average per elapsed day", value: DurationText.work(summary.averageSeconds))
            LabeledContent("Completed / Interrupted", value: "\(summary.completedCount) / \(summary.interruptedCount)")
            if summary.includesActive { Text("Includes current session").font(.footnote).foregroundStyle(.secondary) }
            Chart(summary.days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.focusSeconds / 60))
                    .foregroundStyle(day.isFuture ? Color.gray : Color.indigo)
            }
            .frame(height: 180)
            .accessibilityLabel("Daily focus in minutes. Day-by-day values are listed below.")
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle()).onTapGesture { location in
                        if let frame = proxy.plotFrame, let date: Date = proxy.value(atX: location.x - geometry[frame].origin.x) {
                            selectedDay = date
                        }
                    }
                }
            }
        }
        Section("Comparison") {
            Text("Current: \(comparison.current.start.formatted()) – \(comparison.current.end.formatted())").font(.caption)
            Text("Previous: \(comparison.previous.start.formatted()) – \(comparison.previous.end.formatted())").font(.caption)
            Text("\(comparison.delta >= 0 ? "+" : "−")\(DurationText.work(abs(comparison.delta)))")
            if let percentage = comparison.percentage { Text("\(percentage, specifier: "%.1f")% change") }
        }
        Section("Projects") {
            ForEach(summary.projects) { project in LabeledContent(project.name, value: DurationText.work(project.seconds)) }
        }
        Section("Daily focus") {
            ForEach(summary.days) { day in
                Button { selectedDay = day.date } label: {
                    HStack {
                        Text(day.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(day.isFuture ? "Upcoming" : DurationText.work(day.focusSeconds))
                    }
                }
                if !day.isFuture {
                    Text(day.targetMinutes == nil ? "No recorded goal" : day.targetMinutes == 0 ? "Rest day" : "Goal: \(DurationText.work(Double(day.targetMinutes! * 60)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func move(_ value: Int) {
        let c = GoalEngine.calendar()
        let start = Statistics.interval(for: period, containing: anchor).start
        anchor = c.date(byAdding: period == .week ? .day : .month, value: period == .week ? value * 7 : value, to: start)!
    }
    private func savedSessions(day: DateInterval?) -> [FocusSession] {
        store.state.sessions.filter { session in
            (projectID == nil || session.projectID == projectID) && (day == nil || Statistics.overlap(start: session.startedAt, end: session.endedAt, interval: day!) > 0 || (session.duration == 0 && session.startedAt >= day!.start && session.startedAt < day!.end))
        }.sorted { $0.startedAt > $1.startedAt }
    }
    private func sessionRows(_ sessions: [FocusSession], day: DateInterval?) -> some View {
        ForEach(sessions) { session in
            NavigationLink { SessionDetailView(store: store, sessionID: session.id) } label: {
                SessionRow(session: session, name: store.projectName(session.projectID), day: day)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { Button("Delete", systemImage: "trash") { requestDeletion(session) }.tint(.red) }
            .contextMenu { Button("Delete Session", systemImage: "trash", role: .destructive) { requestDeletion(session) } }
            .accessibilityAction(named: "Delete Session") { requestDeletion(session) }
        }
    }
    private func requestDeletion(_ session: FocusSession) { pendingDeletion = session; confirmingDeletion = true }
}

struct SessionRow: View {
    let session: FocusSession
    let name: String
    var day: DateInterval? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.headline)
            if let intention = session.intention { Text(intention).font(.subheadline).lineLimit(2) }
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
