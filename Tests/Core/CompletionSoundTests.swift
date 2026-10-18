import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class CompletionSoundTests: XCTestCase {
    func testGentleSoundsRoundTripAndRespectInstallationSupport() throws {
        for sound in [CompletionSound.mellow, .wood, .ripple] {
            var state = AppSnapshot()
            state.settings.notificationSound = true
            state.settings.focusCompletionSound = sound
            state.settings.breakCompletionSound = sound
            let restored = try BackupService.decode(BackupService.encode(state))
            XCTAssertEqual(restored.settings.focusCompletionSound, sound)
            XCTAssertEqual(restored.settings.breakCompletionSound, sound)
            #if NATIVE_INTEGRATIONS
            let expected = sound
            #else
            let expected = CompletionSound.systemDefault
            #endif
            XCTAssertEqual(restored.settings.completionSound(for: .focus), expected)
            XCTAssertEqual(restored.settings.completionSound(for: .shortBreak), expected)
        }
    }

    func testCapturedSoundAndMasterMuteSurviveMigrationAndSettingsChanges() throws {
        var state = try BackupService.decode(MigrationFixtures.data("v1-running"), forBackup: false)
        XCTAssertEqual(state.activeTimer?.completionSound, .silent)
        XCTAssertEqual(state.settings.focusCompletionSound, .systemDefault)
        state.settings.notificationSound = true
        XCTAssertEqual(state.activeTimer?.completionSound, .silent)
        XCTAssertEqual(state.settings.completionSound(for: .focus), .systemDefault)
        state.settings.notificationSound = false
        XCTAssertEqual(state.settings.completionSound(for: .shortBreak), .silent)
        XCTAssertEqual(try BackupService.decode(BackupService.encode(state, forBackup: false), forBackup: false), state)
    }
}
