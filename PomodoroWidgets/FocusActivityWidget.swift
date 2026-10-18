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
            FocusActivityCard(state: context.state, stale: context.isStale)
                .widgetURL(url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                        Text(context.state.title)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimerText(state: context.state, stale: context.isStale)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FocusExpandedSessionContent(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "timer")
            }
              compactTrailing: {
                  ActivityTimerText(state: context.state, stale: context.isStale)
                      .multilineTextAlignment(.trailing)
                      .frame(width: 52, alignment: .trailing)
              }
              minimal: {
                  Image(systemName: "timer")
              }
            .widgetURL(url)
        }
    }
}

private struct ActivityPlanText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FocusActivityCard: View {
    let state: LiveActivityProjection
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Image(systemName: "timer").font(.headline)
                        Text(state.title).font(.headline)
                    }
                    if let name = state.projectName {
                        Text(name).font(.subheadline).lineLimit(1)
                    }
                    ActivityTimerText(state: state, stale: stale).font(.title.monospacedDigit())
                }
                Spacer(minLength: 0)
                Link(destination: AppURLRouter(scheme: .native).url(for: state.actionRoute)) {
                    Label(state.kind == "focus" ? "Thought" : "Plan next", systemImage: "square.and.pencil").font(.subheadline)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .frame(minHeight: 44)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel(state.kind == "focus" ? "Add a thought" : "Plan next session")
            }
            if let intention = state.intention { ActivityPlanText(text: intention) }
            if stale { Text("Open Pomodoro to review your session.").font(.caption) }
        }
        .padding()
    }
}

private struct FocusExpandedSessionContent: View {
    let state: LiveActivityProjection

    var body: some View {
        HStack(spacing: 12) {
            if state.projectName != nil || state.intention != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let name = state.projectName { Text(name).lineLimit(1) }
                    if let intention = state.intention { ActivityPlanText(text: intention) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            Link(destination: AppURLRouter(scheme: .native).url(for: state.actionRoute)) {
                Group {
                    if state.kind == "focus" {
                        Image(systemName: "square.and.pencil")
                    } else {
                        Label("Plan next", systemImage: "square.and.pencil")
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel(state.kind == "focus" ? "Add a thought" : "Plan next session")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
private struct FocusActivityPreviews: PreviewProvider {
    private static var state: LiveActivityProjection {
        var snapshot = AppSnapshot(projects: [Project(name: "Reading")])
        snapshot.activeTimer = ActiveTimer(projectID: snapshot.projects[0].id, kind: .focus,
            startedAt: Date(), plannedSeconds: 1500, shortBreakMinutes: 5, longBreakMinutes: 15,
            longBreakInterval: 4, intention: "Read chapter two\nWrite a short summary")
        snapshot.settings.showProjectNameOnLockScreen = true
        snapshot.settings.showIntentionOnLockScreen = true
        return LiveActivityProjection(state: snapshot)!
    }

    static var previews: some View {
        Group {
            FocusActivityCard(state: state, stale: false)
                .previewDisplayName("Lock Screen with session plan")
            FocusExpandedSessionContent(state: state)
                .padding()
                .previewDisplayName("Expanded island with session plan")
        }
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
    }
}
#endif
