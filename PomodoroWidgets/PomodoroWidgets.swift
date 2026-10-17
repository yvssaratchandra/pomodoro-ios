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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if family == .systemSmall { Label("Pomodoro", systemImage: "timer").font(.headline) }
            primaryContent
            if family == .systemMedium {
                Spacer(minLength: 0)
                HStack {
                    if let summary = entry.snapshot?.savedFocus,
                       summary.isFresh(at: entry.date) {
                        Text("Today · \(DurationText.summary(min(summary.seconds, Double(Int.max / 2)))) saved")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Link(destination: router.url(for: entry.snapshot?.thoughtRoute ?? .captureThought(sessionID: nil))) {
                        Label("Thought", systemImage: "square.and.pencil")
                            .font(.caption.weight(.medium))
                            .padding(.vertical, 8).padding(.horizontal, 10)
                            .frame(minWidth: 44, minHeight: 44)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Add a thought")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
        .widgetURL(router.url(for: entry.snapshot?.route(for: entry.selectedID) ?? .timer))
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

@main struct PomodoroWidgets: WidgetBundle {
    var body: some Widget {
        FocusWidget()
        FocusActivityWidget()
    }
}
