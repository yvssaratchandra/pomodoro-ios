import ActivityKit
import Foundation

struct FocusActivityAttributes: ActivityAttributes {
    typealias ContentState = LiveActivityProjection
    let timerID: UUID
}
