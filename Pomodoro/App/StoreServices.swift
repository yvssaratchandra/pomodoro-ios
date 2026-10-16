import Foundation
import UserNotifications

@MainActor protocol SnapshotPersistence {
    func load() throws -> Data?
    func save(_ payload: Data) throws
}

@MainActor protocol SnapshotPublishing {
    func publish(_ state: AppSnapshot, now: Date) throws
}

@MainActor protocol LiveActivityManaging {
    func synchronize(with state: AppSnapshot) async
}

@MainActor struct NoOpSnapshotPublisher: SnapshotPublishing {
    func publish(_ state: AppSnapshot, now: Date) throws {}
}

@MainActor struct NoOpLiveActivityManager: LiveActivityManaging {
    func synchronize(with state: AppSnapshot) async {}
}

// Keep notification delivery unchanged while allowing failed-save tests to
// prove that no permission request, schedule, or cancellation escaped the store.
@MainActor protocol TimerNotificationCenter {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
}

@MainActor struct SystemTimerNotificationCenter: TimerNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeAllPendingNotificationRequests() {
        center.removeAllPendingNotificationRequests()
    }
}
