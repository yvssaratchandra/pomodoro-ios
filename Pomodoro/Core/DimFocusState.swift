import Foundation

/// Presentation state only. Session timing and persistence remain owned by the store.
struct DimFocusState: Equatable {
    static let revealDuration: TimeInterval = 10

    private(set) var sessionID: UUID?
    private(set) var isDimmed = false
    private(set) var generation: UInt64 = 0
    private(set) var returnDeadline: TimeInterval?
    private(set) var blockers: Set<String> = []
    private(set) var interactionCount = 0
    private var eligibleSessionID: UUID?
    private var focusVisible = false
    private var sceneActive = false
    private var accessibilityActive = false

    var isEnabled: Bool { sessionID != nil }
    var canPresent: Bool {
        isEnabled && eligibleSessionID == sessionID && focusVisible && sceneActive && blockers.isEmpty && interactionCount == 0
    }
    var shouldKeepAwake: Bool { isDimmed && canPresent }

    mutating func update(sessionID eligibleID: UUID?, focusVisible: Bool, sceneActive: Bool,
                         accessibilityActive: Bool, uptime: TimeInterval) {
        let changed = eligibleSessionID != eligibleID || self.focusVisible != focusVisible ||
            self.sceneActive != sceneActive || self.accessibilityActive != accessibilityActive
        guard changed else { return }
        eligibleSessionID = eligibleID
        self.focusVisible = focusVisible
        self.sceneActive = sceneActive
        self.accessibilityActive = accessibilityActive
        if let sessionID, sessionID != eligibleID { disable(); return }
        // Returning from the background or another screen always reveals first.
        isDimmed = false
        resetReturn(uptime: uptime)
    }

    mutating func enable(uptime: TimeInterval) {
        guard let eligibleSessionID else { return }
        sessionID = eligibleSessionID
        // The enabling button may still be finishing its touch sequence.
        interactionCount = 0
        invalidateReturn()
        isDimmed = canPresent
        if !isDimmed { resetReturn(uptime: uptime) }
    }

    mutating func disable() {
        sessionID = nil
        isDimmed = false
        invalidateReturn()
    }

    mutating func reveal(uptime: TimeInterval) {
        isDimmed = false
        resetReturn(uptime: uptime)
    }

    mutating func setBlocked(_ key: String, _ blocked: Bool, uptime: TimeInterval) {
        let changed = blocked ? blockers.insert(key).inserted : blockers.remove(key) != nil
        guard changed else { return }
        isDimmed = false
        resetReturn(uptime: uptime)
    }

    mutating func beginInteraction(uptime: TimeInterval) {
        interactionCount += 1
        isDimmed = false
        resetReturn(uptime: uptime)
    }

    mutating func endInteraction(uptime: TimeInterval) {
        interactionCount = max(0, interactionCount - 1)
        resetReturn(uptime: uptime)
    }

    mutating func returnToDim(sessionID expectedID: UUID, generation expectedGeneration: UInt64,
                             uptime: TimeInterval) {
        guard sessionID == expectedID, generation == expectedGeneration,
              canPresent, !accessibilityActive, let returnDeadline, uptime >= returnDeadline else { return }
        isDimmed = true
        invalidateReturn()
    }

    private mutating func invalidateReturn() {
        generation &+= 1
        returnDeadline = nil
    }

    private mutating func resetReturn(uptime: TimeInterval) {
        invalidateReturn()
        if canPresent && !isDimmed && !accessibilityActive {
            returnDeadline = uptime + Self.revealDuration
        }
    }
}
