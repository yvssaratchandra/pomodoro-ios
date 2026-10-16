import SwiftUI
import WidgetKit

private struct FocusEntry: TimelineEntry {
    let date: Date
}

private struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry { FocusEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        completion(FocusEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        completion(Timeline(entries: [FocusEntry(date: Date())], policy: .never))
    }
}

private struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PomodoroFocus", provider: FocusProvider()) { _ in
            VStack(alignment: .leading, spacing: 8) {
                Label("Pomodoro", systemImage: "timer")
                    .font(.headline)
                Text("Open the app to start focusing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Pomodoro")
        .description("Open Pomodoro for your next focus session.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main struct PomodoroWidgets: WidgetBundle {
    var body: some Widget { FocusWidget() }
}
