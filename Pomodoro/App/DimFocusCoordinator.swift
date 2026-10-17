import SwiftUI
import UIKit

@MainActor
final class DimFocusCoordinator: ObservableObject {
    @Published private(set) var state = DimFocusState()
    private var returnTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var scheduledGeneration: UInt64?
    private var watchedDeadline: Date?
    private let awake = DimScreenAwakeService()
    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    var isDimmed: Bool { state.isDimmed && state.canPresent }
    var shouldKeepAwake: Bool { state.shouldKeepAwake }

    func update(timer: ActiveTimer?, focusVisible: Bool, sceneActive: Bool,
                accessibilityActive: Bool, now: Date = Date()) {
        let eligible = timer.flatMap { $0.kind == .focus && $0.deadline > now ? $0.id : nil }
        let eventUptime = uptime
        change { $0.update(sessionID: eligible, focusVisible: focusVisible, sceneActive: sceneActive,
                           accessibilityActive: accessibilityActive, uptime: eventUptime) }
        let deadline = eligible == nil ? nil : timer?.deadline
        if watchedDeadline != deadline {
            expiryTask?.cancel()
            watchedDeadline = deadline
            if let deadline {
                expiryTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
                    catch { return }
                    guard let self, !Task.isCancelled, self.watchedDeadline == deadline else { return }
                    self.disable()
                }
            }
        }
        synchronize()
    }

    func enable() {
        guard let watchedDeadline, watchedDeadline > Date() else { disable(); return }
        let eventUptime = uptime
        change { $0.enable(uptime: eventUptime) }
    }
    func disable() { change { $0.disable() } }
    func reveal() {
        let eventUptime = uptime
        change { $0.reveal(uptime: eventUptime) }
    }
    func setBlocked(_ key: String, _ blocked: Bool) {
        let eventUptime = uptime
        change { $0.setBlocked(key, blocked, uptime: eventUptime) }
    }
    func beginInteraction() {
        let eventUptime = uptime
        change { $0.beginInteraction(uptime: eventUptime) }
    }
    func endInteraction() {
        let eventUptime = uptime
        change { $0.endInteraction(uptime: eventUptime) }
    }
    private func change(_ event: (inout DimFocusState) -> Void) {
        var candidate = state
        event(&candidate)
        if candidate != state { state = candidate }
        synchronize()
    }

    private func synchronize() {
        awake.setHeld(state.shouldKeepAwake)
        guard scheduledGeneration != state.generation else { return }
        returnTask?.cancel()
        scheduledGeneration = state.generation
        guard let deadline = state.returnDeadline, let sessionID = state.sessionID else { return }
        let generation = state.generation
        returnTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0, deadline - ProcessInfo.processInfo.systemUptime))) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            guard let deadline = self.watchedDeadline, deadline > Date() else { self.disable(); return }
            let eventUptime = self.uptime
            self.change { $0.returnToDim(sessionID: sessionID, generation: generation, uptime: eventUptime) }
        }
    }

    deinit {
        returnTask?.cancel()
        expiryTask?.cancel()
        // SwiftUI owns this coordinator on the main thread.
        let service = awake
        Task { @MainActor in service.setHeld(false) }
    }
}

@MainActor
private final class DimScreenAwakeService {
    private var previousValue: Bool?
    func setHeld(_ held: Bool) {
        if held, previousValue == nil {
            previousValue = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        } else if !held, let previousValue {
            UIApplication.shared.isIdleTimerDisabled = previousValue
            self.previousValue = nil
        }
    }
}
