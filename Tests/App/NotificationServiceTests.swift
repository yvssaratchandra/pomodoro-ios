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
}

@MainActor private final class PreviewNotificationCenter: TimerNotificationCenter {
    var granted = true
    var soundEnabled = true
    var authorizationRequests = 0
    var additions = 0
    var pending: [String: UNNotificationRequest] = [:]
    var holdNextAdd = false
    var onAdd: (() -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequests += 1
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
    }
    func release() { continuation?.resume(); continuation = nil }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        for id in identifiers { pending.removeValue(forKey: id) }
    }
    func removeAllPendingNotificationRequests() { pending.removeAll() }
}
