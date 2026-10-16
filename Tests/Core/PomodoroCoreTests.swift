import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class PomodoroCoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    func fixture() -> AppSnapshot { AppSnapshot(projects: [Project(name: "Writing"), Project(name: "Study")]) }

    func testInterruptedWorkCountsAndDoesNotAdvanceCycle() throws {
        var state = fixture()
        let id = state.projects[0].id
        try TimerEngine.startFocus(&state, projectID: id, minutes: 25, now: now)
        TimerEngine.finish(&state, now: now.addingTimeInterval(123), force: true)
        XCTAssertEqual(state.sessions[0].outcome, .interrupted)
        XCTAssertEqual(Statistics.total(state, now: now), 123)
        XCTAssertEqual(state.completedInCycle, 0)
        XCTAssertNil(state.breakOffer)
    }

    func testExpiredSessionIsCappedAndFinalizedOnceAfterRelaunch() throws {
        var state = fixture()
        try TimerEngine.startFocus(&state, projectID: state.projects[0].id, minutes: 10, now: now)
        state = try BackupService.decode(BackupService.encode(state, forBackup: false), forBackup: false)
        XCTAssertEqual(Statistics.total(state, now: now.addingTimeInterval(9999)), 600)
        XCTAssertTrue(TimerEngine.finish(&state, now: now.addingTimeInterval(9999)))
        XCTAssertFalse(TimerEngine.finish(&state, now: now.addingTimeInterval(10000)))
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertEqual(state.sessions[0].outcome, .completed)
        XCTAssertEqual(state.sessions[0].duration, 600)
        XCTAssertNil(state.activeTimer)
        XCTAssertEqual(Statistics.total(state, now: now), 600)
    }

    func testLongBreakAcrossProjectsAndBreakTimeExcluded() throws {
        var state = fixture()
        state.settings.longBreakInterval = 2
        for index in 0..<2 {
            let start = now.addingTimeInterval(Double(index) * 2000)
            try TimerEngine.startFocus(&state, projectID: state.projects[index].id, minutes: 10, now: start)
            TimerEngine.finish(&state, now: start.addingTimeInterval(600))
        }
        XCTAssertEqual(state.breakOffer?.kind, .longBreak)
        XCTAssertEqual(state.completedInCycle, 0)
        try TimerEngine.startBreak(&state, now: now.addingTimeInterval(3000))
        XCTAssertEqual(state.activeTimer?.plannedSeconds, 900)
        TimerEngine.finish(&state, now: now.addingTimeInterval(3900))
        XCTAssertEqual(state.sessions.count, 2)
        XCTAssertEqual(Statistics.total(state, now: now), 1200)
        XCTAssertNil(state.activeTimer)
        XCTAssertNil(state.breakOffer)
    }

    func testSelectionDoesNotChangeAssignmentAndActiveConfigurationIsCaptured() throws {
        var state = fixture()
        let original = state.projects[0].id
        try TimerEngine.startFocus(&state, projectID: original, minutes: 10, now: now)
        state.projects[0].shortBreakMinutes = 12
        state.settings.longBreakInterval = 1
        XCTAssertEqual(Statistics.total(state, projectID: state.projects[1].id, now: now.addingTimeInterval(60)), 0)
        XCTAssertThrowsError(try TimerEngine.startFocus(&state, projectID: state.projects[1].id, minutes: 10, now: now))
        TimerEngine.finish(&state, now: now.addingTimeInterval(600))
        XCTAssertEqual(state.sessions[0].projectID, original)
        XCTAssertEqual(state.breakOffer?.minutes, 5)
        XCTAssertEqual(state.breakOffer?.kind, .shortBreak)
    }

    func testBoundsAndInactiveProjects() throws {
        var state = fixture()
        let id = state.projects[0].id
        for minutes in [9, 61] {
            XCTAssertThrowsError(try TimerEngine.startFocus(&state, projectID: id, minutes: minutes, now: now))
        }
        state.projects[0].status = .suspended
        XCTAssertThrowsError(try TimerEngine.startFocus(&state, projectID: id, minutes: 10, now: now))
        state.projects[0].status = .completed
        XCTAssertThrowsError(try TimerEngine.startFocus(&state, projectID: id, minutes: 10, now: now))
    }

    func testMidnightSplitAndSevenDayAverageIncludeZeroDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.startOfDay(for: now)
        var state = fixture()
        let id = state.projects[0].id
        try TimerEngine.startFocus(&state, projectID: id, minutes: 20, now: midnight.addingTimeInterval(-600))
        TimerEngine.finish(&state, now: midnight.addingTimeInterval(600))
        let day = Statistics.today(midnight, calendar: calendar)
        XCTAssertEqual(Statistics.total(state, interval: day, now: midnight), 600)
        XCTAssertEqual(Statistics.total(state, interval: Statistics.today(midnight.addingTimeInterval(-1), calendar: calendar), now: midnight), 600)
        XCTAssertEqual(Statistics.dailyAverage(state, projectID: id, now: midnight, calendar: calendar), 1200.0 / 7, accuracy: 0.001)
        XCTAssertEqual(Statistics.sessionsToday(state, now: midnight, calendar: calendar).count, 1)
    }

    func testDSTUsesCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
        let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 12))!
        let autumn = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        XCTAssertEqual(Statistics.today(spring, calendar: calendar).duration, 23 * 3600)
        XCTAssertEqual(Statistics.today(autumn, calendar: calendar).duration, 25 * 3600)
    }

    func testMergePreservesTimeAndDestinationSettings() throws {
        var state = fixture()
        let source = state.projects[0].id
        let destination = state.projects[1]
        try TimerEngine.startFocus(&state, projectID: source, minutes: 10, now: now)
        XCTAssertThrowsError(try TimerEngine.merge(&state, source: source, destination: destination.id))
        TimerEngine.finish(&state, now: now.addingTimeInterval(600))
        let before = Statistics.total(state, now: now)
        try TimerEngine.merge(&state, source: source, destination: destination.id)
        XCTAssertEqual(state.projects, [destination])
        XCTAssertEqual(state.sessions[0].projectID, destination.id)
        XCTAssertEqual(state.breakOffer?.projectID, destination.id)
        XCTAssertEqual(Statistics.total(state, now: now), before)
    }

    func testBackupRoundTripAndInvalidData() throws {
        var state = fixture()
        let id = state.projects[0].id
        try TimerEngine.startFocus(&state, projectID: id, minutes: 10, now: now)
        XCTAssertThrowsError(try BackupService.encode(state))
        TimerEngine.finish(&state, now: now.addingTimeInterval(600))
        XCTAssertEqual(try BackupService.decode(BackupService.encode(state)), state)
        var invalid = state
        invalid.schemaVersion = 999
        XCTAssertThrowsError(try BackupService.validate(invalid))
        invalid = state
        invalid.sessions[0].projectID = UUID()
        XCTAssertThrowsError(try BackupService.validate(invalid))
        invalid = state
        invalid.projects.append(invalid.projects[0])
        XCTAssertThrowsError(try BackupService.validate(invalid))
        XCTAssertThrowsError(try BackupService.decode(Data("invalid".utf8)))
    }

    func testClockBeforeStartDoesNotProduceNegativeWork() throws {
        var state = fixture()
        try TimerEngine.startFocus(&state, projectID: state.projects[0].id, minutes: 10, now: now)
        XCTAssertEqual(Statistics.total(state, now: now.addingTimeInterval(-30)), 0)
        TimerEngine.finish(&state, now: now.addingTimeInterval(-30), force: true)
        XCTAssertEqual(state.sessions[0].duration, 0)
    }

    func testBackupPreservesSubsecondWorkAcrossMinuteBoundary() throws {
        var state = fixture()
        let start = now.addingTimeInterval(0.75)
        try TimerEngine.startFocus(&state, projectID: state.projects[0].id, minutes: 10, now: start)
        TimerEngine.finish(&state, now: start.addingTimeInterval(59.75), force: true)
        let restored = try BackupService.decode(BackupService.encode(state))
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.sessions[0].duration, 59.75)
        XCTAssertEqual(DurationText.work(restored.sessions[0].duration), "59 sec")
    }

    func testRememberedDurationsSupportOldBackupsAndRoundTrip() throws {
        var state = fixture()
        state.projects[0].focusMinutes = 30
        state.projects[0].lastFocusMinutes = 40
        state.projects[1].lastFocusMinutes = 15
        let data = try BackupService.encode(state)
        let restored = try BackupService.decode(data)
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.projects.map(\.preferredFocusMinutes), [40, 15])

        // Simulate an existing v1 backup produced before duration memory existed.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var projects = try XCTUnwrap(json["projects"] as? [[String: Any]])
        for index in projects.indices { projects[index].removeValue(forKey: "lastFocusMinutes") }
        json["projects"] = projects
        let oldData = try JSONSerialization.data(withJSONObject: json)
        let oldBackup = try BackupService.decode(oldData)
        XCTAssertEqual(oldBackup.projects.map(\.preferredFocusMinutes), [30, 25])
        XCTAssertNil(oldBackup.projects[0].lastFocusMinutes)
    }

    func testInvalidRememberedDurationRejectedOnImport() throws {
        var state = fixture()
        for minutes in [9, 61] {
            state.projects[0].lastFocusMinutes = minutes
            XCTAssertThrowsError(try BackupService.encode(state))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .deferredToDate
            XCTAssertThrowsError(try BackupService.decode(encoder.encode(state)))
        }
    }

    func testMergeKeepsDestinationDurationPreference() throws {
        var state = fixture()
        state.projects[0].lastFocusMinutes = 40
        state.projects[1].lastFocusMinutes = 15
        let destination = state.projects[1].id
        try TimerEngine.merge(&state, source: state.projects[0].id, destination: destination)
        XCTAssertEqual(state.projects.count, 1)
        XCTAssertEqual(state.projects[0].id, destination)
        XCTAssertEqual(state.projects[0].preferredFocusMinutes, 15)
    }
}
