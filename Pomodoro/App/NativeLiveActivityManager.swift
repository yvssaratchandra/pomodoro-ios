#if NATIVE_INTEGRATIONS
import ActivityKit
import UIKit
import OSLog

@MainActor struct NativeLiveActivityManager: LiveActivityManaging {
    func synchronize(with state: AppSnapshot) async {
        let projection = LiveActivityProjection(state: state)
        var retained: Activity<FocusActivityAttributes>?
        for activity in Activity<FocusActivityAttributes>.activities {
            if let projection, projection.deadline > Date(), activity.attributes.timerID == projection.id, retained == nil {
                retained = activity
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard let projection, projection.deadline > Date() else { return }
        let content = ActivityContent(state: projection, staleDate: projection.deadline)
        if let retained {
            await retained.update(content)
        } else if ActivityAuthorizationInfo().areActivitiesEnabled, UIApplication.shared.applicationState == .active {
            do {
                _ = try Activity.request(attributes: FocusActivityAttributes(timerID: projection.id), content: content, pushType: nil)
            } catch {
                Logger(subsystem: "Pomodoro", category: "LiveActivities").error("Unable to start Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
#endif
