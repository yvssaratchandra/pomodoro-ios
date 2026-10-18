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
    private func actionURL(_ state: LiveActivityProjection) -> URL {
        AppURLRouter(scheme: .native).url(for: state.actionRoute)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Image("PomodoroMark").resizable().scaledToFit().frame(width: 18, height: 18)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(context.state.title).font(.headline)
                        }
                        if let name = context.state.projectName {
                            Text(name).font(.subheadline).lineLimit(1)
                        }
                        ActivityTimerText(state: context.state, stale: context.isStale).font(.title.monospacedDigit())
                    }
                    Spacer(minLength: 0)
                    Link(destination: actionURL(context.state)) {
                        Label(context.state.kind == "focus" ? "Thought" : "Plan next", systemImage: "square.and.pencil").font(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .frame(minHeight: 44)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel(context.state.kind == "focus" ? "Add a thought" : "Plan next session")
                }
                if let intention = context.state.intention { Text(intention).font(.caption).lineLimit(2) }
                if context.isStale { Text("Open Pomodoro to review your session.").font(.caption) }
            }
            .padding()
            .widgetURL(url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image("PomodoroMark").resizable().scaledToFit().frame(width: 16, height: 16)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        Text(context.state.title)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimerText(state: context.state, stale: context.isStale)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        if context.state.projectName != nil || context.state.intention != nil {
                            VStack(alignment: .leading, spacing: 4) {
                                if let name = context.state.projectName { Text(name).lineLimit(1) }
                                if let intention = context.state.intention { Text(intention).font(.caption).lineLimit(2) }
                            }
                        }
                        Link(destination: actionURL(context.state)) {
                            Group {
                                if context.state.kind == "focus" {
                                    Image(systemName: "square.and.pencil")
                                } else {
                                    Label("Plan next", systemImage: "square.and.pencil")
                                }
                            }
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel(context.state.kind == "focus" ? "Add a thought" : "Plan next session")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image("PomodoroMark").resizable().scaledToFit().frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
              compactTrailing: {
                  ActivityTimerText(state: context.state, stale: context.isStale)
                      .multilineTextAlignment(.trailing)
                      .frame(width: 52, alignment: .trailing)
              }
              minimal: {
                  Image("PomodoroMark").resizable().scaledToFit().frame(width: 16, height: 16)
                      .clipShape(RoundedRectangle(cornerRadius: 3))
              }
            .widgetURL(url)
        }
    }
}
