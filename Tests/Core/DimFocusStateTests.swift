import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class DimFocusStateTests: XCTestCase {
    private let session = UUID()
    private func enabled() -> DimFocusState {
        var state = DimFocusState()
        state.update(sessionID: session, focusVisible: true, sceneActive: true, accessibilityActive: false, uptime: 0)
        XCTAssertFalse(state.isEnabled)
        state.enable(uptime: 0)
        return state
    }

    func testRevealReturnsOnlyAfterTenSecondsAndMatchingGeneration() {
        var state = enabled()
        XCTAssertTrue(state.shouldKeepAwake)
        state.reveal(uptime: 10)
        let generation = state.generation
        XCTAssertFalse(state.shouldKeepAwake)
        state.returnToDim(sessionID: session, generation: generation, uptime: 19.999)
        XCTAssertFalse(state.isDimmed)
        state.returnToDim(sessionID: session, generation: generation, uptime: 20)
        XCTAssertTrue(state.isDimmed)
    }

    func testInteractionAndMultipleBlockersSuspendReturnUntilAllFinish() {
        var state = enabled()
        state.beginInteraction(uptime: 1)
        state.setBlocked("sheet", true, uptime: 2)
        state.setBlocked("keyboard", true, uptime: 3)
        state.endInteraction(uptime: 4)
        state.setBlocked("sheet", false, uptime: 5)
        XCTAssertNil(state.returnDeadline)
        state.setBlocked("keyboard", false, uptime: 6)
        XCTAssertEqual(state.returnDeadline, 16)
        let oldGeneration = state.generation
        state.beginInteraction(uptime: 7)
        state.returnToDim(sessionID: session, generation: oldGeneration, uptime: 20)
        XCTAssertFalse(state.isDimmed)
        state.endInteraction(uptime: 20)
        XCTAssertEqual(state.returnDeadline, 30)
    }

    func testBackgroundReleasesAndForegroundRevealsBeforeFreshDelay() {
        var state = enabled()
        state.update(sessionID: session, focusVisible: true, sceneActive: false, accessibilityActive: false, uptime: 1)
        XCTAssertFalse(state.shouldKeepAwake)
        XCTAssertNil(state.returnDeadline)
        XCTAssertTrue(state.isEnabled)
        state.update(sessionID: session, focusVisible: true, sceneActive: true, accessibilityActive: false, uptime: 10)
        XCTAssertFalse(state.isDimmed)
        XCTAssertEqual(state.returnDeadline, 20)
    }

    func testSessionReplacementExpiryAndDisableRejectOldWork() {
        for replacement in [UUID?.none, UUID?.some(UUID())] {
            var state = enabled()
            state.reveal(uptime: 1)
            let generation = state.generation
            state.update(sessionID: replacement, focusVisible: true, sceneActive: true, accessibilityActive: false, uptime: 2)
            XCTAssertFalse(state.isEnabled)
            state.returnToDim(sessionID: session, generation: generation, uptime: 100)
            XCTAssertFalse(state.isDimmed)
        }
        var state = enabled()
        state.reveal(uptime: 1)
        let generation = state.generation
        state.disable()
        state.returnToDim(sessionID: session, generation: generation, uptime: 100)
        XCTAssertFalse(state.isDimmed)
    }

    func testAccessibilityAllowsManualDimButPreventsAutomaticReturn() {
        var state = DimFocusState()
        state.update(sessionID: session, focusVisible: true, sceneActive: true, accessibilityActive: true, uptime: 0)
        state.enable(uptime: 0)
        XCTAssertTrue(state.isDimmed)
        state.reveal(uptime: 1)
        XCTAssertNil(state.returnDeadline)
        state.enable(uptime: 2)
        XCTAssertTrue(state.isDimmed)
    }

    func testCaptureDismissalStartsFreshDelayAfterFinalPresentationBlockerClears() {
        var state = enabled()
        state.setBlocked("capture", true, uptime: 1)
        state.setBlocked("keyboard", true, uptime: 2)
        state.setBlocked("external-sheet", true, uptime: 3)
        state.setBlocked("capture", false, uptime: 20)
        XCTAssertFalse(state.isDimmed)
        XCTAssertNil(state.returnDeadline)
        state.setBlocked("keyboard", false, uptime: 21)
        XCTAssertNil(state.returnDeadline)
        state.setBlocked("external-sheet", false, uptime: 22)
        XCTAssertFalse(state.isDimmed)
        XCTAssertEqual(state.returnDeadline, 32)
        let generation = state.generation
        state.returnToDim(sessionID: session, generation: generation, uptime: 31.999)
        XCTAssertFalse(state.isDimmed)
        state.returnToDim(sessionID: session, generation: generation, uptime: 32)
        XCTAssertTrue(state.isDimmed)
    }

    func testEmptyCaptureDismissalUsesNormalInactivityDelay() {
        var state = enabled()
        state.setBlocked("capture", true, uptime: 1)
        state.setBlocked("capture", false, uptime: 2)
        XCTAssertFalse(state.isDimmed)
        XCTAssertEqual(state.returnDeadline, 12)
    }

    func testManualEnableIsImmediateWhileEnablingTouchFinishes() {
        var state = enabled()
        state.reveal(uptime: 1)
        state.beginInteraction(uptime: 2)
        state.enable(uptime: 2)
        XCTAssertTrue(state.isDimmed)
        state.endInteraction(uptime: 3)
        XCTAssertTrue(state.isDimmed)
        XCTAssertNil(state.returnDeadline)
    }

    func testRepeatedEnvironmentUpdatesDoNotRestartInactivity() {
        var state = enabled()
        state.reveal(uptime: 1)
        let generation = state.generation
        state.update(sessionID: session, focusVisible: true, sceneActive: true, accessibilityActive: false, uptime: 3)
        XCTAssertEqual(state.generation, generation)
        XCTAssertEqual(state.returnDeadline, 11)
    }

    func testSwitchingAwayFromFocusSuspendsAndRevealsOnReturn() {
        var state = enabled()
        state.update(sessionID: session, focusVisible: false, sceneActive: true, accessibilityActive: false, uptime: 1)
        XCTAssertNil(state.returnDeadline)
        XCTAssertFalse(state.isDimmed)
        state.update(sessionID: session, focusVisible: true, sceneActive: true, accessibilityActive: false, uptime: 10)
        XCTAssertEqual(state.returnDeadline, 20)
    }
}
