import ActivityKit
import SwiftUI
import WidgetKit

private struct ActivityTimerText: View {
    let state: LiveActivityProjection
    let stale: Bool
    var body: some View {
        if stale { Text("00:00").monospacedDigit() }
        else { Text(timerInterval: state.startedAt...state.deadline, countsDown: true).monospacedDigit() }
    }
}

struct FocusActivityWidget: Widget {
    private let url = AppURLRouter(scheme: .native).url(for: .timer)
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label(context.state.title, systemImage: "timer").font(.headline)
                ActivityTimerText(state: context.state, stale: context.isStale).font(.largeTitle)
                if let name = context.state.projectName { Text(name).font(.subheadline).lineLimit(1) }
                if let intention = context.state.intention { Text(intention).font(.caption).lineLimit(2) }
                if context.isStale { Text("Open Pomodoro to review your session.").font(.caption) }
            }
            .padding()
            .widgetURL(url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label(context.state.title, systemImage: "timer") }
                DynamicIslandExpandedRegion(.trailing) { ActivityTimerText(state: context.state, stale: context.isStale) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack {
                        if let name = context.state.projectName { Text(name).lineLimit(1) }
                        if let intention = context.state.intention { Text(intention).font(.caption).lineLimit(2) }
                    }
                }
            } compactLeading: { Image(systemName: "timer") }
              compactTrailing: { ActivityTimerText(state: context.state, stale: context.isStale).frame(width: 52) }
              minimal: { Image(systemName: "timer") }
            .widgetURL(url)
        }
    }
}
