import XCTest
import UserNotifications
@testable import Pomodoro

@MainActor final class NotificationServiceTests: XCTestCase {
    func testOverlappingPreviewsKeepTheNewerRequest() async throws {
        let center = PreviewNotificationCenter()
        let service = NotificationService(center: center, now: Date.init)
        let adding = expectation(description: "First preview starts adding")
        center.onAdd = { adding.fulfill() }
        center.holdNextAdd = true
        let first = Task { try await service.test(sound: .bell) }
        await fulfillment(of: [adding], timeout: 2)
        center.onAdd = nil
        let second = Task { try await service.test(sound: .chime) }
        await Task.yield()
        center.release()
        _ = try await first.value
        let result = try await second.value
        XCTAssertTrue(result.contains("scheduled"))
        XCTAssertEqual(center.additions, 2)
        XCTAssertEqual(center.pending.keys.sorted(), ["completion-sound-test"])
    }

    func testMutingAnInFlightPreviewRemovesItsLateRequest() async throws {
        let center = PreviewNotificationCenter()
        let service = NotificationService(center: center, now: Date.init)
        let adding = expectation(description: "Preview starts adding")
        center.onAdd = { adding.fulfill() }
        center.holdNextAdd = true
        let first = Task { try await service.test(sound: .bell) }
        await fulfillment(of: [adding], timeout: 2)
        let muted = try await service.test(sound: .silent)
        XCTAssertEqual(muted, "Sound is off.")
        center.release()
        _ = try await first.value
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(center.authorizationRequests, 1)
    }

    func testDeniedAndSoundDisabledPreviewsNeverAddRequests() async throws {
        let center = PreviewNotificationCenter()
        let service = NotificationService(center: center, now: Date.init)
        center.granted = false
        let denied = try await service.test(sound: .systemDefault)
        XCTAssertTrue(denied.contains("Allow notifications"))
        center.granted = true
        center.soundEnabled = false
        let disabled = try await service.test(sound: .bell)
        XCTAssertTrue(disabled.contains("sounds are disabled"))
        XCTAssertEqual(center.additions, 0)
    }

    func testRapidSoundUpdateKeepsLatestRequestAtOriginalDeadline() async throws {
        let center = PreviewNotificationCenter()
        let clock = NotificationClock()
        let service = NotificationService(center: center, now: { clock.date })
        let timer = makeTimer(now: clock.date, sound: .bell)
        let firstAdding = expectation(description: "First timer request starts adding")
        let latestAdded = expectation(description: "Latest timer sound is scheduled")
        center.onAdd = { firstAdding.fulfill() }
        center.onAddCompleted = { request in
            if request.identifier == "timer.\(timer.id.uuidString)", request.content.sound == nil {
                latestAdded.fulfill()
            }
        }
        center.holdNextAdd = true
        service.schedule(timer: timer, project: "Writing", isCurrent: { true }, expired: {}, failed: { XCTFail($0) })
        await fulfillment(of: [firstAdding], timeout: 2)
        center.onAdd = nil

        var updated = timer
        updated.completionSound = .chime
        service.schedule(timer: updated, project: "Writing", isCurrent: { true }, expired: {}, failed: { XCTFail($0) })
        updated.completionSound = .silent
        service.schedule(timer: updated, project: "Writing", isCurrent: { true }, expired: {}, failed: { XCTFail($0) })
        center.release()

        await fulfillment(of: [latestAdded], timeout: 2)
        let request = try XCTUnwrap(center.pending["timer.\(timer.id.uuidString)"])
        XCTAssertEqual(center.pending.count, 1)
        XCTAssertNil(request.content.sound)
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, timer.deadline.timeIntervalSince(clock.date), accuracy: 1)
    }

    func testCancellationRemovesRequestWhoseAddWasSuspended() async throws {
        let center = PreviewNotificationCenter()
        let clock = NotificationClock()
        let service = NotificationService(center: center, now: { clock.date })
        let timer = makeTimer(now: clock.date, sound: .bell)
        let adding = expectation(description: "Timer request starts adding")
        let added = expectation(description: "Suspended add completes")
        let removed = expectation(description: "Cancelled request is removed")
        center.onAdd = { adding.fulfill() }
        center.onAddCompleted = { _ in added.fulfill() }
        center.onRemove = { id in if id == "timer.\(timer.id.uuidString)" { removed.fulfill() } }
        center.holdNextAdd = true
        var current = true
        service.schedule(timer: timer, project: "Writing", isCurrent: { current }, expired: {}, failed: { XCTFail($0) })
        await fulfillment(of: [adding], timeout: 2)
        current = false
        service.cancel(timerID: timer.id)
        await fulfillment(of: [removed], timeout: 2)
        let lateRemoval = expectation(description: "Late request is removed")
        center.onRemove = { id in if id == "timer.\(timer.id.uuidString)" { lateRemoval.fulfill() } }
        center.release()
        await fulfillment(of: [added, lateRemoval], timeout: 2)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testExpiryDuringAuthorizationDoesNotScheduleLateAlert() async throws {
        let center = PreviewNotificationCenter()
        let clock = NotificationClock()
        let service = NotificationService(center: center, now: { clock.date })
        let timer = makeTimer(now: clock.date, sound: .bell)
        let authorizing = expectation(description: "Timer asks for authorization")
        let expired = expectation(description: "Timer expiry is reconciled")
        center.onAuthorization = { authorizing.fulfill() }
        center.holdNextAuthorization = true
        service.schedule(timer: timer, project: "Writing", isCurrent: { true }, expired: { expired.fulfill() }, failed: { XCTFail($0) })
        await fulfillment(of: [authorizing], timeout: 2)
        clock.date = timer.deadline.addingTimeInterval(1)
        center.releaseAuthorization()
        await fulfillment(of: [expired], timeout: 2)
        XCTAssertEqual(center.additions, 0)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testExpiryDuringAddDoesNotLeaveLatePendingRequest() async throws {
        let center = PreviewNotificationCenter()
        let clock = NotificationClock()
        let service = NotificationService(center: center, now: { clock.date })
        let timer = makeTimer(now: clock.date, sound: .bell)
        let adding = expectation(description: "Timer request starts adding")
        let removed = expectation(description: "Expired late request is removed")
        center.onAdd = { adding.fulfill() }
        center.onRemove = { id in if id == "timer.\(timer.id.uuidString)" { removed.fulfill() } }
        center.holdNextAdd = true
        service.schedule(timer: timer, project: "Writing", isCurrent: { true }, expired: {}, failed: { XCTFail($0) })
        await fulfillment(of: [adding], timeout: 2)
        clock.date = timer.deadline.addingTimeInterval(1)
        service.naturalCompletion(timerID: timer.id)
        center.release()
        await fulfillment(of: [removed], timeout: 2)
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testOlderAddCannotReplaceNewTimer() async throws {
        let center = PreviewNotificationCenter()
        let clock = NotificationClock()
        let service = NotificationService(center: center, now: { clock.date })
        let old = makeTimer(now: clock.date, sound: .bell)
        let newer = makeTimer(now: clock.date, sound: .chime)
        let oldAdding = expectation(description: "Old timer starts adding")
        let oldRemoved = expectation(description: "Old timer request is removed")
        let newAdded = expectation(description: "New timer request is scheduled")
        center.onAdd = { oldAdding.fulfill() }
        center.onRemove = { id in if id == "timer.\(old.id.uuidString)" { oldRemoved.fulfill() } }
        center.onAddCompleted = { request in
            if request.identifier == "timer.\(newer.id.uuidString)" { newAdded.fulfill() }
        }
        center.holdNextAdd = true
        var currentID = old.id
        service.schedule(timer: old, project: "Old", isCurrent: { currentID == old.id }, expired: {}, failed: { XCTFail($0) })
        await fulfillment(of: [oldAdding], timeout: 2)
        center.onAdd = nil
        currentID = newer.id
        service.schedule(timer: newer, project: "New", isCurrent: { currentID == newer.id }, expired: {}, failed: { XCTFail($0) })
        center.release()
        await fulfillment(of: [oldRemoved, newAdded], timeout: 2)
        XCTAssertEqual(center.pending.keys.sorted(), ["timer.\(newer.id.uuidString)"])
        XCTAssertTrue(center.pending.values.first?.content.body.contains("New") == true)
        XCTAssertNotNil(center.pending.values.first?.content.sound)
    }

    func testDeniedAuthorizationReportsAnExplicitAudioUpdateFailure() async {
        let center = PreviewNotificationCenter()
        center.granted = false
        let service = NotificationService(center: center, now: Date.init)
        let failed = expectation(description: "Audio update reports disabled notifications")
        service.schedule(timer: makeTimer(now: Date(), sound: .silent), project: "Writing", isCurrent: { true },
                         expired: {}, failed: { message in
            XCTAssertTrue(message.contains("Notifications are off"))
            failed.fulfill()
        }, reportAuthorizationFailure: true)
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertTrue(center.pending.isEmpty)
    }

    private func makeTimer(now: Date, sound: CompletionSound) -> ActiveTimer {
        ActiveTimer(projectID: UUID(), kind: .focus, startedAt: now, plannedSeconds: 300,
                    shortBreakMinutes: 5, longBreakMinutes: 15, longBreakInterval: 4,
                    intention: nil, completionSound: sound)
    }

}

@MainActor private final class NotificationClock {
    var date = Date()
}

@MainActor private final class PreviewNotificationCenter: TimerNotificationCenter {
    var granted = true
    var soundEnabled = true
    var authorizationRequests = 0
    var additions = 0
    var pending: [String: UNNotificationRequest] = [:]
    var holdNextAdd = false
    var onAdd: (() -> Void)?
    var onAddCompleted: ((UNNotificationRequest) -> Void)?
    var onRemove: ((String) -> Void)?
    var holdNextAuthorization = false
    var onAuthorization: (() -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequests += 1
        if holdNextAuthorization {
            holdNextAuthorization = false
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                onAuthorization?()
            }
        }
        return granted
    }
    func soundIsEnabled() async -> Bool { soundEnabled }
    func add(_ request: UNNotificationRequest) async throws {
        additions += 1
        if holdNextAdd {
            holdNextAdd = false
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onAdd?()
            }
        }
        pending[request.identifier] = request
        onAddCompleted?(request)
    }
    func release() { continuation?.resume(); continuation = nil }
    func releaseAuthorization() { authorizationContinuation?.resume(); authorizationContinuation = nil }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        for id in identifiers {
            pending.removeValue(forKey: id)
            onRemove?(id)
        }
    }
    func removeAllPendingNotificationRequests() { pending.removeAll() }
}
