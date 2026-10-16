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
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
    }
}

private struct FocusWidgetView: View {
    let entry: FocusEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pomodoro", systemImage: "timer").font(.headline)
            if let timer = entry.snapshot?.activeTimer {
                Text(timer.kind.title).font(.subheadline)
                Text(timer.projectName).lineLimit(2)
                Text(timerInterval: timer.startedAt...timer.deadline, countsDown: true)
                    .font(.title2.monospacedDigit())
                Text("Open timer").font(.caption).foregroundStyle(.secondary)
            } else if let snapshot = entry.snapshot {
                if let project = snapshot.projects.first(where: { $0.id == entry.selectedID }) {
                    Text(project.name).font(.subheadline).lineLimit(2)
                    Text("Start \(project.preferredFocusMinutes) min").font(.title3.weight(.semibold))
                } else {
                    Text(snapshot.projects.isEmpty ? "Create a project" : "Choose a project in Edit Widget")
                        .font(.subheadline)
                }
            } else {
                Text("Open Pomodoro to connect this widget.").font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.background, for: .widget)
        .widgetURL(AppURLRouter(scheme: .native).url(for: entry.snapshot?.route(for: entry.selectedID) ?? .timer))
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
