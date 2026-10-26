import SwiftUI
import Charts

private struct HistoryDay: Identifiable {
    let date: Date
    let sessions: [FocusSession]
    var id: Date { date }
}
private struct StatsProjectSettingsRequest: Identifiable {
    let projectID: UUID
    let page: ProjectSettingsPage
    var id: String { "\(projectID)-\(page)" }
}

struct StatsView: View {
    @Bindable var store: AppStore
    @State private var selection = StatsDateSelection()
    @State private var showingDatePicker = false
    @State private var calendarDate = Date()
    @State private var projectID: UUID?
    @State private var showConsistency = false
    @State private var settingsRequest: StatsProjectSettingsRequest?
    private var range: StatsDateRange { selection.range }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let now = timeline.date
                let interval = selection.interval(now: now)
                let sessions = savedSessions(in: interval)
                let hasFocusInProgress = Statistics.hasFocusInProgress(store.state, projectID: projectID, interval: interval, now: now)
                List {
                    Section {
                        Picker("Range", selection: Binding(get: { range }, set: { selection.setRange($0) })) {
                            ForEach(StatsDateRange.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("stats.range")
                        if let interval { periodNavigation(interval: interval, now: now) }
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Focus time").font(.subheadline).foregroundStyle(.secondary)
                            Text(DurationText.summary(Statistics.total(store.state, projectID: projectID, interval: interval, now: now)))
                                .font(.largeTitle.bold())
                                .accessibilityIdentifier("stats.savedFocusTime")
                            if hasFocusInProgress {
                                Text("1 session in progress · not included yet")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("stats.sessionInProgress")
                            }
                            if range == .day, let interval, let projectID,
                               let goal = GoalEngine.dailyTarget(projectID: projectID, on: interval.start, plan: store.state.goalPlan) {
                                dailyGoal(goal, projectID: projectID, interval: interval, now: now)
                            }
                            if range == .week, let interval, let projectID,
                               let target = GoalEngine.weeklyTarget(projectID: projectID, weekStart: interval.start, plan: store.state.goalPlan) {
                                weeklyGoal(target, projectID: projectID, now: now)
                            }
                        }.padding(.vertical, 5)
                    }
                    if let period = range.period, let interval {
                        periodOverview(period: period, interval: interval, now: now)
                    }
                    Section("Recent sessions") {
                        if sessions.isEmpty {
                            ContentUnavailableView("No saved sessions", systemImage: "timer")
                        } else {
                            if range == .day {
                                sessionRows(Array(sessions.prefix(5)), day: interval)
                            } else {
                                ForEach(grouped(Array(sessions.prefix(5)))) { group in
                                    Text(group.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                    sessionRows(group.sessions)
                                }
                            }
                            if sessions.count > 5 {
                                NavigationLink("View all sessions") {
                                    historyView(interval: interval, title: "Sessions", day: range == .day ? interval : nil)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(AppTheme.surface)
                .appScreen()
            }
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            projectID = nil
                        } label: {
                            if projectID == nil { Label("All projects", systemImage: "checkmark") }
                            else { Text("All projects") }
                        }
                        ForEach(store.state.projects) { project in
                            Button {
                                projectID = project.id
                            } label: {
                                if projectID == project.id { Label(project.name, systemImage: "checkmark") }
                                else { Text(project.name) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "line.3.horizontal.decrease")
                            if let projectID {
                                Text(store.projectName(projectID)).lineLimit(1)
                            }
                        }
                    }
                    .accessibilityLabel(projectID.map { "Project: \(store.projectName($0))" } ?? "All projects")
                    .accessibilityIdentifier("stats.project")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showConsistency = true } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Consistency")
                    .accessibilityIdentifier("stats.consistency")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                selection.reconcile(now: Date())
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                selection.reconcile(now: Date())
            }
            .onChange(of: store.state.projects.map(\.id)) { _, ids in
                if let projectID, !ids.contains(projectID) { self.projectID = nil }
            }
            .navigationDestination(isPresented: $showConsistency) {
                ConsistencyDetailsView(store: store)
            }
            .sheet(isPresented: $showingDatePicker) {
                StatsDatePicker(date: calendarDate) { date in
                    selection.select(date, now: Date())
                }
            }
            .sheet(item: $settingsRequest) { request in
                if let project = store.state.projects.first(where: { $0.id == request.projectID }) {
                    ProjectEditor(store: store, project: project, initialPage: request.page)
                } else {
                    ContentUnavailableView("Project unavailable", systemImage: "folder",
                        description: Text("Return to Stats and select another project."))
                }
            }
            .alert("Unable to delete", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
                Button("OK") { deletionError = nil }
            } message: { Text(deletionError ?? "") }
        }
    }
    @State private var deletionError: String?

    @ViewBuilder private func periodNavigation(interval: DateInterval, now: Date) -> some View {
        HStack(spacing: 8) {
            Button {
                selection.move(-1, now: now)
            } label: {
                Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Previous \(range.rawValue.lowercased())")
            .accessibilityIdentifier("stats.previous")
            Spacer(minLength: 0)
            Button {
                calendarDate = min(interval.start, now)
                showingDatePicker = true
            } label: {
                HStack(spacing: 5) {
                    Text(dateLabel(interval: interval, now: now))
                        .font(.subheadline).multilineTextAlignment(.center)
                    Image(systemName: "calendar").font(.caption).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel(dateLabel(interval: interval, now: now))
            .accessibilityValue(interval.start.formatted(date: .complete, time: .omitted))
            .accessibilityHint("Choose a date")
            .accessibilityIdentifier("stats.date")
            Spacer(minLength: 0)
            Button {
                selection.move(1, now: now)
            } label: {
                Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!selection.canMoveForward(now: now))
            .accessibilityLabel("Next \(range.rawValue.lowercased())")
            .accessibilityIdentifier("stats.next")
        }
        // List's automatic style can invoke every button in the row from one tap.
        .buttonStyle(.borderless)
        if !selection.isCurrent(now: now) {
            Button(currentPeriodTitle) { selection.resetToCurrent() }
                .frame(minHeight: 44)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("stats.current")
        }
    }

    private var currentPeriodTitle: String {
        switch range {
        case .day: "Today"
        case .week: "This week"
        case .month: "This month"
        case .all: "All"
        }
    }

    private func dateLabel(interval: DateInterval, now: Date) -> String {
        switch range {
        case .day:
            let date = interval.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
            return selection.isCurrent(now: now) ? "Today · \(date)" : date
        case .week:
            let end = GoalEngine.calendar().date(byAdding: .day, value: -1, to: interval.end)!
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day().year())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year())
        case .all:
            return "All"
        }
    }

    @ViewBuilder private func dailyGoal(_ goal: Int, projectID: UUID, interval: DateInterval, now: Date) -> some View {
        if selection.isCurrent(now: now) {
            Button {
                settingsRequest = StatsProjectSettingsRequest(projectID: projectID, page: .daily)
            } label: {
                HStack {
                    Text(goal == 0 ? "Rest day" : "of \(DurationText.summary(Double(goal * 60)))")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text("Edit goal").font(.subheadline)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stats.dailyGoal")
        } else {
            LabeledContent("Goal on this day", value: goal == 0 ? "Rest day" : DurationText.summary(Double(goal * 60)))
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("stats.historicalDailyGoal")
        }
        if goal > 0 {
            let worked = Statistics.total(store.state, projectID: projectID, interval: interval, now: now)
            ProgressView(value: min(worked, Double(goal * 60)), total: Double(goal * 60))
                .accessibilityLabel("Daily goal")
        }
    }

    @ViewBuilder private func weeklyGoal(_ target: Int, projectID: UUID, now: Date) -> some View {
        if selection.isCurrent(now: now) {
            Button {
                settingsRequest = StatsProjectSettingsRequest(projectID: projectID, page: .weekly)
            } label: {
                LabeledContent("Weekly goal", value: DurationText.summary(Double(target * 60)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } else {
            LabeledContent("Weekly goal", value: DurationText.summary(Double(target * 60)))
                .font(.subheadline).foregroundStyle(.secondary)
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
            .accessibilityHint("Open Details for values and sessions")
            Text(comparisonText(comparison, period: period, current: interval.end > now))
                .font(.subheadline).foregroundStyle(.secondary)
            NavigationLink("Details") { periodDetails(period: period, interval: interval) }
        }
    }

    private func comparisonText(_ comparison: PeriodComparison, period: FocusPeriod, current: Bool) -> String {
        let name = period == .week ? "week" : "month"
        let suffix = current ? " so far" : ""
        if comparison.delta == 0 { return "Same as last \(name)\(suffix)" }
        return "\(DurationText.summary(abs(comparison.delta))) \(comparison.delta > 0 ? "more" : "less") than last \(name)\(suffix)"
    }

    private func periodDetails(period: FocusPeriod, interval: DateInterval) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let summary = Statistics.periodSummary(store.state, interval: interval, projectID: projectID, now: now)
            let comparison = Statistics.periodComparison(store.state, period: period, interval: interval,
                                                         projectID: projectID, now: now)
            List {
                Section("Daily breakdown") {
                    ForEach(summary.days.filter { !$0.isFuture }) { day in
                        NavigationLink {
                            historyView(interval: Statistics.today(day.date),
                                        title: day.date.formatted(date: .abbreviated, time: .omitted),
                                        day: Statistics.today(day.date))
                        } label: {
                            LabeledContent(day.date.formatted(date: .abbreviated, time: .omitted),
                                           value: DurationText.summary(day.focusSeconds))
                        }
                    }
                }
                Section("Overview") {
                    LabeledContent("Daily average", value: DurationText.summary(summary.averageSeconds))
                    LabeledContent("Completed", value: "\(summary.completedCount)")
                    LabeledContent("Ended early", value: "\(summary.interruptedCount)")
                }
                Section("Comparison") {
                    LabeledContent("This period", value: DurationText.summary(comparison.currentSeconds))
                    LabeledContent("Previous period", value: DurationText.summary(comparison.previousSeconds))
                    Text("This period: \(comparison.current.start.formatted(date: .abbreviated, time: .omitted)) – \(comparison.current.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Previous period: \(comparison.previous.start.formatted(date: .abbreviated, time: .omitted)) – \(comparison.previous.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let percentage = comparison.percentage {
                        LabeledContent("Change", value: String(format: "%+.1f%%", percentage))
                    }
                    Text(interval.end > now ? "Compared with the same calendar days in the previous period, including the full matching day." : "Compared with the full previous period.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if projectID == nil && !summary.projects.isEmpty {
                    Section("Projects") {
                        ForEach(summary.projects) { project in
                            LabeledContent(project.name, value: DurationText.summary(project.seconds))
                        }
                    }
                }
                if summary.days.contains(where: { $0.targetMinutes == nil }) {
                    Section { Text("Older dates may not have a recorded goal.") }
                }
            }.appScreen()
        }.navigationTitle("Details")
    }
    private func historyView(interval: DateInterval?, title: String, day: DateInterval? = nil) -> some View {
        let sessions = savedSessions(in: interval)
        return List {
            if sessions.isEmpty {
                ContentUnavailableView("No saved sessions", systemImage: "timer")
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

private struct StatsDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State var date: Date
    let select: (Date) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker("Choose a date", selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .environment(\.calendar, GoalEngine.calendar())
                    .accessibilityIdentifier("stats.datePicker")
                    .padding()
            }
            .appScreen()
            .navigationTitle("Choose a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("stats.datePicker.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        select(date)
                        dismiss()
                    }
                    .accessibilityIdentifier("stats.datePicker.done")
                }
            }
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
            if let firstTask = SessionPlanText.items(from: session.intention).first {
                Text(firstTask).font(.subheadline).lineLimit(1)
            }
            HStack {
                Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(DurationText.summary(session.duration))")
                if session.outcome != .completed { Text("Ended early") }
            }.font(.subheadline).foregroundStyle(.secondary)
            if let day, session.startedAt < day.start || session.endedAt > day.end {
                Text("This day: \(DurationText.summary(Statistics.overlap(start: session.startedAt, end: session.endedAt, interval: day)))")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("session.\(session.outcome.rawValue)")
    }
}
