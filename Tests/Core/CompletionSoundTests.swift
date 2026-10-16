import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class CompletionSoundTests: XCTestCase {
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
