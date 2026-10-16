import SwiftUI
import Charts

private enum HistoryRange: String, CaseIterable, Identifiable {
    case today = "Today", week = "Week", month = "Month", all = "All"
    var id: String { rawValue }
    var period: FocusPeriod? {
        switch self { case .week: .week; case .month: .month; default: nil }
    }
}
private struct HistoryDay: Identifiable {
    let date: Date
    let sessions: [FocusSession]
    var id: Date { date }
}

struct StatsView: View {
    @Bindable var store: AppStore
    @State private var range: HistoryRange = .today
    @State private var anchor = Date()
    @State private var projectID: UUID?
    @State private var selectedDay: Date?
    @State private var showConsistency = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let now = timeline.date
                let interval = selectedInterval(now: now)
                let sessions = savedSessions(in: interval)
                let active = matchingActiveTimer(in: interval, now: now)
                List {
                    Section {
                        Picker("Range", selection: $range) {
                            ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Picker("Project", selection: $projectID) {
                            Text("All projects").tag(Optional<UUID>.none)
                            ForEach(store.state.projects) { Text($0.name).tag(Optional($0.id)) }
                        }
                        if range.period != nil { periodNavigation(now: now) }
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Focus time").font(.subheadline).foregroundStyle(.secondary)
                            Text(DurationText.work(Statistics.total(store.state, projectID: projectID, interval: interval, now: now)))
                                .font(.largeTitle.bold())
                        }.padding(.vertical, 5)
                        if range == .today && projectID == nil,
                           let goal = GoalEngine.dailyTarget(on: now, plan: store.state.goalPlan) {
                            if goal > 0 {
                                let worked = Statistics.total(store.state, interval: interval, now: now)
                                ProgressView(value: min(worked, Double(goal * 60)), total: Double(goal * 60))
                                    .accessibilityLabel("Daily goal")
                                NavigationLink("Goal: \(DurationText.work(Double(goal * 60)))") { GoalsView(store: store) }
                            } else { Text("Rest day").foregroundStyle(.secondary) }
                        }
                        if range == .week, let projectID,
                           let target = GoalEngine.weeklyTarget(projectID: projectID, weekStart: anchor, plan: store.state.goalPlan) {
                            LabeledContent("Weekly goal", value: DurationText.work(Double(target * 60)))
                        }
                    }
                    if let period = range.period, let interval {
                        periodOverview(period: period, interval: interval, now: now)
                    }
                    Section("Recent sessions") {
                        if let active {
                            LabeledContent(store.projectName(active.projectID), value: "In progress")
                        }
                        if sessions.isEmpty && active == nil {
                            ContentUnavailableView("No sessions in this selection", systemImage: "timer")
                        } else {
                            ForEach(grouped(Array(sessions.prefix(5)))) { group in
                                Text(group.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundStyle(.secondary)
                                sessionRows(group.sessions, day: range == .today ? interval : nil)
                            }
                            NavigationLink("View all sessions") {
                                historyView(interval: interval, title: "Sessions")
                            }
                        }
                    }
                }
                .listRowBackground(AppTheme.surface)
                .appScreen()
            }
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Consistency", systemImage: "calendar.badge.checkmark") { showConsistency = true }
                        NavigationLink { GoalsView(store: store) } label: {
                            Label("Goals", systemImage: "target")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More statistics")
                }
            }
            .onChange(of: range) { _, _ in anchor = Date() }
            .onChange(of: store.state.projects.map(\.id)) { _, ids in
                if let projectID, !ids.contains(projectID) { self.projectID = nil }
            }
            .navigationDestination(isPresented: $showConsistency) {
                ConsistencyDetailsView(state: store.state)
            }
            .navigationDestination(isPresented: Binding(get: { selectedDay != nil }, set: { if !$0 { selectedDay = nil } })) {
                if let selectedDay {
                    historyView(interval: Statistics.today(selectedDay),
                                title: selectedDay.formatted(date: .abbreviated, time: .omitted),
                                day: Statistics.today(selectedDay))
                }
            }
            .alert("Unable to delete", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
                Button("OK") { deletionError = nil }
            } message: { Text(deletionError ?? "") }
        }
    }
    @State private var deletionError: String?

    @ViewBuilder private func periodNavigation(now: Date) -> some View {
        if let period = range.period {
            let interval = Statistics.interval(for: period, containing: anchor)
            HStack {
                Button("Previous", systemImage: "chevron.left") { move(-1) }.labelStyle(.iconOnly)
                Spacer()
                Text(period == .week
                     ? "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(interval.end.addingTimeInterval(-1).formatted(.dateTime.month(.abbreviated).day()))"
                     : interval.start.formatted(.dateTime.month(.wide).year()))
                    .font(.subheadline).multilineTextAlignment(.center)
                Spacer()
                Button("Next", systemImage: "chevron.right") { move(1) }
                    .labelStyle(.iconOnly).disabled(interval.end > now)
            }
        }
    }

    @ViewBuilder private func periodOverview(period: FocusPeriod, interval: DateInterval, now: Date) -> some View {
        let summary = Statistics.periodSummary(store.state, interval: interval, projectID: projectID, now: now)
        let comparison = Statistics.periodComparison(store.state, period: period, interval: interval, projectID: projectID, now: now)
        Section {
            Chart(summary.days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.focusSeconds / 60))
                    .foregroundStyle(day.isFuture ? Color.gray.opacity(0.35) : Color.indigo)
            }
            .frame(height: 155)
            .accessibilityLabel("Daily focus chart")
            .accessibilityHint("Open Daily breakdown for values and sessions")
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle()).onTapGesture { location in
                        if let frame = proxy.plotFrame {
                            let plot = geometry[frame]
                            guard plot.contains(location),
                                  let date: Date = proxy.value(atX: location.x - plot.origin.x), date <= now else { return }
                            selectedDay = date
                        }
                    }
                }
            }
            Text(comparisonText(comparison, period: period, current: interval.end > now))
                .font(.subheadline).foregroundStyle(.secondary)
            NavigationLink("Daily breakdown") { dailyBreakdown(summary: summary) }
            NavigationLink("Details") { periodDetails(summary: summary, comparison: comparison) }
        }
        if projectID == nil && !summary.projects.isEmpty {
            Section("Projects") {
                ForEach(summary.projects.prefix(3)) { project in
                    LabeledContent(project.name, value: DurationText.work(project.seconds))
                }
                if summary.projects.count > 3 {
                    NavigationLink("All projects") {
                        List(summary.projects) { project in
                            LabeledContent(project.name, value: DurationText.work(project.seconds))
                        }.appScreen().navigationTitle("Projects")
                    }
                }
            }
        }
    }

    private func comparisonText(_ comparison: PeriodComparison, period: FocusPeriod, current: Bool) -> String {
        let name = period == .week ? "week" : "month"
        let suffix = current ? " so far" : ""
        if abs(comparison.delta) < 1 { return "Same as last \(name)\(suffix)" }
        return "\(DurationText.work(abs(comparison.delta))) \(comparison.delta > 0 ? "more" : "less") than last \(name)\(suffix)"
    }

    private func dailyBreakdown(summary: PeriodSummary) -> some View {
        List {
            ForEach(summary.days.filter { !$0.isFuture }) { day in
                Button { selectedDay = day.date } label: {
                    LabeledContent(day.date.formatted(date: .abbreviated, time: .omitted),
                                   value: DurationText.work(day.focusSeconds))
                }
            }
        }.appScreen().navigationTitle("Daily breakdown")
    }
    private func periodDetails(summary: PeriodSummary, comparison: PeriodComparison) -> some View {
        List {
            Section("Overview") {
                LabeledContent("Daily average", value: DurationText.work(summary.averageSeconds))
                LabeledContent("Completed", value: "\(summary.completedCount)")
                LabeledContent("Ended early", value: "\(summary.interruptedCount)")
                if summary.includesActive { Text("Includes the current session").foregroundStyle(.secondary) }
            }
            Section("Comparison") {
                LabeledContent("This period", value: DurationText.work(comparison.currentSeconds))
                LabeledContent("Previous period", value: DurationText.work(comparison.previousSeconds))
                Text("This period: \(comparison.current.start.formatted()) – \(comparison.current.end.formatted())")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Previous period: \(comparison.previous.start.formatted()) – \(comparison.previous.end.formatted())")
                    .font(.caption).foregroundStyle(.secondary)
                if let percentage = comparison.percentage {
                    LabeledContent("Change", value: String(format: "%+.1f%%", percentage))
                }
                Text("Compared through the same point in the previous period when this period is still in progress.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if summary.days.contains(where: { $0.targetMinutes == nil }) {
                Section { Text("Older dates may not have a recorded goal.") }
            }
        }.appScreen().navigationTitle("Details")
    }
    private func historyView(interval: DateInterval?, title: String, day: DateInterval? = nil) -> some View {
        let sessions = savedSessions(in: interval)
        return List {
            if sessions.isEmpty {
                ContentUnavailableView("No sessions", systemImage: "timer")
            } else {
                ForEach(grouped(sessions)) { group in
                    Section(group.date.formatted(date: .complete, time: .omitted)) {
                        sessionRows(group.sessions, day: day)
                    }
                }
            }
        }.appScreen().navigationTitle(title)
    }
    private func grouped(_ sessions: [FocusSession]) -> [HistoryDay] {
        let groups = Dictionary(grouping: sessions) { GoalEngine.calendar().startOfDay(for: $0.startedAt) }
        return groups.keys.sorted(by: >).map {
            HistoryDay(date: $0, sessions: groups[$0]!.sorted { $0.startedAt > $1.startedAt })
        }
    }
    private func matchingActiveTimer(in interval: DateInterval?, now: Date) -> ActiveTimer? {
        guard let timer = store.state.activeTimer, timer.kind == .focus,
              projectID == nil || projectID == timer.projectID else { return nil }
        if let interval {
            let end = timer.startedAt.addingTimeInterval(timer.elapsed(at: now))
            guard Statistics.overlap(start: timer.startedAt, end: end, interval: interval) > 0 else { return nil }
        }
        return timer
    }
    private func selectedInterval(now: Date) -> DateInterval? {
        switch range {
        case .today: Statistics.today(now)
        case .week, .month: Statistics.interval(for: range.period!, containing: anchor)
        case .all: nil
        }
    }
    private func move(_ value: Int) {
        guard let period = range.period else { return }
        let c = GoalEngine.calendar()
        let start = Statistics.interval(for: period, containing: anchor).start
        anchor = c.date(byAdding: period == .week ? .day : .month,
                        value: period == .week ? value * 7 : value, to: start)!
    }
    private func savedSessions(in interval: DateInterval?) -> [FocusSession] {
        store.state.sessions.filter { session in
            guard projectID == nil || session.projectID == projectID else { return false }
            guard let interval else { return true }
            return Statistics.overlap(start: session.startedAt, end: session.endedAt, interval: interval) > 0 ||
                (session.duration == 0 && session.startedAt >= interval.start && session.startedAt < interval.end)
        }.sorted { $0.startedAt > $1.startedAt }
    }
    private func sessionRows(_ sessions: [FocusSession], day: DateInterval? = nil) -> some View {
        ForEach(sessions) { session in
            NavigationLink { SessionDetailView(store: store, sessionID: session.id) } label: {
                SessionRow(session: session, name: store.projectName(session.projectID), day: day,
                           hideProject: projectID != nil)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Delete", systemImage: "trash", role: .destructive) { delete(session) }
            }
            .contextMenu { Button("Delete Session", systemImage: "trash", role: .destructive) { delete(session) } }
            .accessibilityAction(named: "Delete Session") { delete(session) }
        }
    }
    private func delete(_ session: FocusSession) {
        if !store.deleteSession(session.id) {
            deletionError = store.errorMessage ?? "The session could not be deleted."
            store.errorMessage = nil
        }
    }
}

struct SessionRow: View {
    let session: FocusSession
    let name: String
    var day: DateInterval? = nil
    var hideProject = false
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !hideProject { Text(name).font(.headline).lineLimit(1) }
            if let intention = session.intention { Text(intention).font(.subheadline).lineLimit(1) }
            HStack {
                Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(DurationText.work(session.duration))")
                if session.outcome != .completed { Text("Ended early") }
            }.font(.subheadline).foregroundStyle(.secondary)
            if let day, session.startedAt < day.start || session.endedAt > day.end {
                Text("This day: \(DurationText.work(Statistics.overlap(start: session.startedAt, end: session.endedAt, interval: day)))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session.\(session.outcome.rawValue)")
    }
}
