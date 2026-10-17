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
    private func thoughtURL(timerID: UUID) -> URL {
        AppURLRouter(scheme: .native).url(for: .captureThought(sessionID: timerID))
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(context.state.title, systemImage: "timer").font(.headline)
                        if let name = context.state.projectName {
                            Text(name).font(.subheadline).lineLimit(1)
                        }
                        ActivityTimerText(state: context.state, stale: context.isStale).font(.title.monospacedDigit())
                    }
                    Spacer(minLength: 0)
                    Link(destination: thoughtURL(timerID: context.attributes.timerID)) {
                        Label("Thought", systemImage: "square.and.pencil").font(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .frame(minHeight: 44)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Add a thought")
                }
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
                    HStack(spacing: 12) {
                        if context.state.projectName != nil || context.state.intention != nil {
                            VStack(alignment: .leading, spacing: 4) {
                                if let name = context.state.projectName { Text(name).lineLimit(1) }
                                if let intention = context.state.intention { Text(intention).font(.caption).lineLimit(2) }
                            }
                        }
                        Link(destination: thoughtURL(timerID: context.attributes.timerID)) {
                            Image(systemName: "square.and.pencil")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Add a thought")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: { Image(systemName: "timer") }
              compactTrailing: { ActivityTimerText(state: context.state, stale: context.isStale).frame(width: 52) }
              minimal: { Image(systemName: "timer") }
            .widgetURL(url)
        }
    }
}
