import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

enum MigrationFixtures {
    static func data(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: SnapshotMigrationTests.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }
}

final class SnapshotMigrationTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800000000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        return calendar
    }

    func testV1HistoryMigrationPreservesEveryLegacyField() throws {
        let original = try MigrationFixtures.data("v1-history")
        let upgraded = try SnapshotMigration.upgrade(data: original, now: now, calendar: calendar)
        var json = try object(upgraded)
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        XCTAssertEqual(settings.removeValue(forKey: "showProjectNameOnLockScreen") as? Bool, false)
        XCTAssertEqual(settings.removeValue(forKey: "showIntentionOnLockScreen") as? Bool, false)
        json["settings"] = settings
        json["schemaVersion"] = 1
        XCTAssertTrue(NSDictionary(dictionary: json).isEqual(to: try object(original)))

        let state = try BackupService.decode(original, now: now, calendar: calendar)
        XCTAssertEqual(state.schemaVersion, BackupService.currentSchemaVersion)
        XCTAssertEqual(state.projects.first?.preferredFocusMinutes, 40)
        XCTAssertEqual(state.projects.first?.createdAt, Date(timeIntervalSinceReferenceDate: 770000000.125))
        XCTAssertEqual(state.sessions.map(\.outcome), [.completed, .interrupted])
        XCTAssertEqual(state.sessions.map(\.duration), [600, 59.75])
        XCTAssertEqual(state.sessions.map(\.startedAt), [Date(timeIntervalSinceReferenceDate: 770000100.75),
                                                       Date(timeIntervalSinceReferenceDate: 770001100.75)])
        XCTAssertTrue(state.sessions.allSatisfy { $0.intention == nil })
        XCTAssertEqual(state.completedInCycle, 1)
        XCTAssertNil(state.breakOffer)
        XCTAssertEqual(state.settings.appearance, .dark)
        XCTAssertFalse(state.settings.notificationSound)
        XCTAssertFalse(state.settings.showProjectNameOnLockScreen)
        XCTAssertFalse(state.settings.showIntentionOnLockScreen)
        XCTAssertEqual(try BackupService.decode(BackupService.encode(state)), state)
    }

    func testV1RunningDocumentKeepsIdentityDeadlineAndCycleWithoutExportingAnActiveBackup() throws {
        let data = try MigrationFixtures.data("v1-running")
        let state = try BackupService.decode(data, forBackup: false, now: now, calendar: calendar)
        let timer = try XCTUnwrap(state.activeTimer)
        XCTAssertEqual(timer.id, UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        XCTAssertEqual(timer.projectID, state.projects.first?.id)
        XCTAssertEqual(timer.startedAt, Date(timeIntervalSinceReferenceDate: 770002100.875))
        XCTAssertEqual(timer.deadline, Date(timeIntervalSinceReferenceDate: 770004500.875))
        XCTAssertEqual(timer.plannedSeconds, 2400)
        XCTAssertEqual(timer.shortBreakMinutes, 5)
        XCTAssertEqual(timer.longBreakMinutes, 15)
        XCTAssertEqual(timer.longBreakInterval, 4)
        XCTAssertNil(timer.intention)
        XCTAssertNil(state.breakOffer)
        XCTAssertEqual(state.completedInCycle, 1)
        XCTAssertEqual(state.sessions.count, 2)
        XCTAssertThrowsError(try BackupService.decode(data))
        XCTAssertThrowsError(try BackupService.encode(state))
        XCTAssertEqual(try BackupService.decode(BackupService.encode(state, forBackup: false), forBackup: false), state)
    }

    func testMigrationPreservesPendingBreakOffer() throws {
        var json = try object(MigrationFixtures.data("v1-history"))
        json["breakOffer"] = ["projectID": "11111111-1111-1111-1111-111111111111",
                              "kind": "shortBreak", "minutes": 5]
        let state = try decode(json)
        XCTAssertEqual(state.breakOffer?.projectID, state.projects.first?.id)
        XCTAssertEqual(state.breakOffer?.kind, .shortBreak)
        XCTAssertEqual(state.breakOffer?.minutes, 5)
        XCTAssertEqual(try BackupService.decode(BackupService.encode(state)), state)
    }

    func testMigrationIsIdempotentAndCurrentBytesAreNotRewritten() throws {
        let source = try MigrationFixtures.data("v1-history")
        let decoded = try BackupService.decodeWithMigration(source, now: now, calendar: calendar)
        XCTAssertTrue(decoded.didMigrate)
        let current = try BackupService.encode(decoded.state)
        XCTAssertEqual(try SnapshotMigration.upgrade(data: current, now: now, calendar: calendar), current)
        XCTAssertFalse(try BackupService.decodeWithMigration(current, now: now, calendar: calendar).didMigrate)
        XCTAssertEqual(AppSnapshot().schemaVersion, BackupService.currentSchemaVersion)
    }

    func testOlderV1WithoutRememberedDurationStillUsesProjectDefault() throws {
        var json = try object(MigrationFixtures.data("v1-history"))
        var projects = try XCTUnwrap(json["projects"] as? [[String: Any]])
        projects[0].removeValue(forKey: "lastFocusMinutes")
        json["projects"] = projects
        let state = try decode(json)
        XCTAssertNil(state.projects.first?.lastFocusMinutes)
        XCTAssertEqual(state.projects.first?.preferredFocusMinutes, 25)
    }

    func testMissingLegacyFieldsAreRejectedInsteadOfReceivingDefaults() throws {
        let original = try object(MigrationFixtures.data("v1-history"))
        for key in ["schemaVersion", "projects", "sessions", "settings", "completedInCycle"] {
            var json = original
            json.removeValue(forKey: key)
            XCTAssertThrowsError(try decode(json), "Missing \(key) must fail")
        }
        var json = original
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings.removeValue(forKey: "haptics")
        json["settings"] = settings
        XCTAssertThrowsError(try decode(json))
        json = original
        var sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        sessions[0].removeValue(forKey: "endedAt")
        json["sessions"] = sessions
        XCTAssertThrowsError(try decode(json))
    }

    func testInvalidLegacyStateAndUnsupportedVersionsAreRejected() throws {
        let original = try object(MigrationFixtures.data("v1-history"))
        let invalidVersions: [Any] = [true, "1", 0, -1, 999, 1.5, NSNull()]
        for version in invalidVersions {
            var json = original
            json["schemaVersion"] = version
            XCTAssertThrowsError(try decode(json), "Invalid version \(version) must fail")
        }
        var json = original
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings["dailyGoalMinutes"] = 0
        json["settings"] = settings
        XCTAssertThrowsError(try decode(json))
        json = original
        var sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        sessions.append(sessions[0])
        json["sessions"] = sessions
        XCTAssertThrowsError(try decode(json))
        XCTAssertThrowsError(try BackupService.decode(Data("not JSON".utf8)))
        XCTAssertThrowsError(try BackupService.decode(Data("[]".utf8)))
    }

    func testCurrentSchemaRequiresPrivacyFieldsAndRetainsOptInsAndIntentions() throws {
        var state = try BackupService.decode(MigrationFixtures.data("v1-history"))
        state.settings.showProjectNameOnLockScreen = true
        state.settings.showIntentionOnLockScreen = true
        state.sessions[0].intention = "Draft the opening paragraph"
        let data = try BackupService.encode(state)
        XCTAssertEqual(try BackupService.decode(data), state)
        var json = try object(data)
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings.removeValue(forKey: "showIntentionOnLockScreen")
        json["settings"] = settings
        XCTAssertThrowsError(try decode(json))
    }

    func testIntentionLimitAppliesToStoredSessionsAndTimersUsingSwiftCharacters() throws {
        let accepted = String(repeating: "👩🏽‍💻", count: 280)
        let rejected = accepted + "x"
        var state = try BackupService.decode(MigrationFixtures.data("v1-running"), forBackup: false)
        state.sessions[0].intention = accepted
        state.activeTimer?.intention = accepted
        XCTAssertEqual(try BackupService.decode(BackupService.encode(state, forBackup: false), forBackup: false), state)
        state.sessions[0].intention = rejected
        XCTAssertThrowsError(try BackupService.encode(state, forBackup: false))
        XCTAssertThrowsError(try BackupService.decode(JSONEncoder().encode(state), forBackup: false))
        state.sessions[0].intention = nil
        state.activeTimer?.intention = rejected
        XCTAssertThrowsError(try BackupService.encode(state, forBackup: false))
        XCTAssertThrowsError(try BackupService.decode(JSONEncoder().encode(state), forBackup: false))
    }

    func testFinishingImportedTimerPreservesItsIntention() throws {
        let original = try BackupService.decode(MigrationFixtures.data("v1-running"), forBackup: false)
        for interrupted in [false, true] {
            var state = original
            state.activeTimer?.intention = "Finish chapter two"
            let timer = try XCTUnwrap(state.activeTimer)
            let end = interrupted ? timer.startedAt.addingTimeInterval(59.75) : timer.deadline
            XCTAssertTrue(TimerEngine.finish(&state, now: end, force: interrupted))
            XCTAssertEqual(state.sessions.last?.id, timer.id)
            XCTAssertEqual(state.sessions.last?.intention, timer.intention)
        }
    }

    func testSizeLimitIsCheckedBeforeParsingOrMigration() {
        XCTAssertThrowsError(try BackupService.decode(Data(repeating: 0x20, count: 50_000_001))) { error in
            XCTAssertEqual(error.localizedDescription, "The backup exceeds the 50 MB limit.")
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> AppSnapshot {
        try BackupService.decode(JSONSerialization.data(withJSONObject: object), forBackup: false,
                                 now: now, calendar: calendar)
    }
}
