import SwiftUI
import WidgetKit
import AppIntents

struct FocusProjectEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static var defaultQuery = FocusProjectQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct FocusProjectQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FocusProjectEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [FocusProjectEntity] {
        (SharedWidgetContainer.read()?.projects ?? []).map { FocusProjectEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

struct FocusConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Focus project"
    static var description = IntentDescription("Choose the project to start from this widget.")
    @Parameter(title: "Project") var project: FocusProjectEntity?
}

private struct FocusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let selectedID: UUID?
}

private struct FocusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FocusEntry { FocusEntry(date: Date(), snapshot: nil, selectedID: nil) }
    func snapshot(for configuration: FocusConfiguration, in context: Context) async -> FocusEntry {
        FocusEntry(date: Date(), snapshot: SharedWidgetContainer.read(), selectedID: configuration.project.flatMap { UUID(uuidString: $0.id) })
    }
    func timeline(for configuration: FocusConfiguration, in context: Context) async -> Timeline<FocusEntry> {
        let entry = await snapshot(for: configuration, in: context)
        var entries = [entry]
        if let midnight = Calendar.current.dateInterval(of: .day, for: entry.date)?.end {
            entries.append(FocusEntry(date: midnight, snapshot: entry.snapshot, selectedID: entry.selectedID))
        }
        return Timeline(entries: entries, policy: .after(WidgetSnapshot.nextRefresh(after: entry.date)))
    }
}

private struct FocusWidgetView: View {
    let entry: FocusEntry
    @Environment(\.widgetFamily) private var family

    private var router: AppURLRouter { AppURLRouter(scheme: .native) }
    private var activeTimer: WidgetSnapshot.Timer? { entry.snapshot?.activeTimer }
    private var shownProjectID: UUID? { activeTimer?.projectID ?? entry.selectedID }
    private var contextRoute: AppRoute {
        guard let timer = activeTimer else { return entry.snapshot?.thoughtRoute ?? .captureThought(sessionID: nil) }
        if timer.kind == .focus { return entry.snapshot?.thoughtRoute ?? .captureThought(sessionID: timer.id) }
        guard let projectID = timer.projectID else { return .timer }
        return .planNextSession(projectID: projectID)
    }

    var body: some View {
        Group {
            if family == .systemMedium { mediumContent }
            else { smallContent }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
        .widgetURL(router.url(for: entry.snapshot?.route(for: entry.selectedID) ?? .timer))
    }

    private var smallContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text("Pomodoro") } icon: {
                Image("PomodoroMark").resizable().scaledToFit().frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }.font(.headline)
            primaryContent
        }
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image("PomodoroMark").resizable().scaledToFit().frame(width: 17, height: 17)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text(displayProjectName).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(activeTimer?.kind.title ?? "Ready").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    if let timer = activeTimer {
                        if timer.deadline <= entry.date {
                            Text("00:00").font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                        } else {
                            Text(timerInterval: timer.startedAt...timer.deadline, countsDown: true)
                                .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                        }
                    } else if let project = entry.snapshot?.projects.first(where: { $0.id == entry.selectedID }) {
                        Text("Start Focus").font(.title3.weight(.semibold))
                        Text("\(project.preferredFocusMinutes) min").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(entry.snapshot?.projects.isEmpty == false ? "Choose a project" : "Create a project")
                            .font(.title3.weight(.semibold)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Link(destination: router.url(for: contextRoute)) {
                    Image(systemName: activeTimer?.kind == .shortBreak || activeTimer?.kind == .longBreak
                          ? "square.and.pencil" : "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))
                }
                .accessibilityLabel(activeTimer?.kind == .shortBreak || activeTimer?.kind == .longBreak
                                    ? "Plan next session" : "Add a thought")
            }
            Spacer(minLength: 0)
            dailyProgress
        }
        .padding(.vertical, 2)
    }

    private var displayProjectName: String {
        if let timer = activeTimer { return timer.projectName }
        return entry.snapshot?.projects.first(where: { $0.id == entry.selectedID })?.name ?? "Pomodoro"
    }

    private var dailyProgress: some View {
        let summary = shownProjectID.flatMap { entry.snapshot?.projectSummary(for: $0, at: entry.date) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let summary {
                    let worked = DurationText.summary(summary.savedFocus.seconds)
                    if let target = summary.targetMinutes, target > 0 {
                        Text("\(worked) / \(DurationText.summary(Double(target * 60)))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else if summary.targetMinutes == 0 {
                        Text("Rest day · \(worked)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Text("\(worked) saved").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if let summary, let target = summary.targetMinutes, target > 0 {
                ProgressView(value: min(summary.savedFocus.seconds, Double(target * 60)), total: Double(target * 60))
                    .tint(AppWidgetTheme.accent)
                    .accessibilityLabel("Project daily goal progress")
            } else {
                Capsule().fill(.quaternary).frame(height: 3)
            }
        }
    }

    @ViewBuilder private var primaryContent: some View {
        if let timer = entry.snapshot?.activeTimer {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(timer.kind.title).font(.subheadline)
                    if family == .systemMedium {
                        Text("·").foregroundStyle(.secondary)
                        Text(timer.projectName).font(.subheadline).lineLimit(1)
                    }
                }
                if family == .systemSmall { Text(timer.projectName).font(.caption).lineLimit(1) }
                if timer.deadline <= entry.date {
                    Text("00:00").font(.title2.monospacedDigit())
                } else {
                    Text(timerInterval: timer.startedAt...timer.deadline, countsDown: true)
                        .font(.title2.monospacedDigit())
                }
                if family == .systemSmall { Text("Open timer").font(.caption).foregroundStyle(.secondary) }
            }
        } else if let snapshot = entry.snapshot {
            if let project = snapshot.projects.first(where: { $0.id == entry.selectedID }) {
                Text(project.name).font(.subheadline).lineLimit(2)
                Text("Start \(project.preferredFocusMinutes) min").font(.title3.weight(.semibold))
            } else {
                Text(snapshot.projects.isEmpty ? "Create a project" : "Choose a project in Edit Widget")
                    .font(.subheadline)
            }
        } else {
            Text("Open Pomodoro to set up widgets").font(.subheadline)
        }
    }
}

struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PomodoroFocus", intent: FocusConfiguration.self, provider: FocusProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick start")
        .description("Start a project or open the current timer.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private enum AppWidgetTheme {
    static let accent = Color(red: 0.49, green: 0.34, blue: 0.94)
}

private struct ThoughtCaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family
    private var route: URL { AppURLRouter(scheme: .native).url(for: .captureThought(sessionID: nil)) }

    var body: some View {
        Group {
            if family == .systemSmall {
                captureLink
                    .containerBackground(.background, for: .widget)
            } else {
                captureLink
                    .containerBackground(.clear, for: .widget)
            }
        }
    }

    private var captureLink: some View {
        Link(destination: route) {
            ZStack(alignment: .bottomTrailing) {
                Image("PomodoroMark")
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: family == .systemSmall ? 15 : 3))
                    .padding(family == .systemSmall ? 30 : 8)
                if family == .systemSmall {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(AppWidgetTheme.accent)
                        .background(.background, in: Circle())
                        .padding(12)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Add a thought")
        }
        .widgetURL(route)
    }
}

private struct ThoughtCaptureEntry: TimelineEntry { let date = Date() }

private struct ThoughtCaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> ThoughtCaptureEntry { ThoughtCaptureEntry() }
    func getSnapshot(in context: Context, completion: @escaping (ThoughtCaptureEntry) -> Void) {
        completion(ThoughtCaptureEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ThoughtCaptureEntry>) -> Void) {
        completion(Timeline(entries: [ThoughtCaptureEntry()], policy: .never))
    }
}

struct ThoughtCaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PomodoroThoughtCapture", provider: ThoughtCaptureProvider()) { _ in
            ThoughtCaptureWidgetView()
        }
        .configurationDisplayName("Add a thought")
        .description("Open Pomodoro's thought capture screen.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

@main struct PomodoroWidgets: WidgetBundle {
    var body: some Widget {
        FocusWidget()
        FocusActivityWidget()
        ThoughtCaptureWidget()
    }
}
