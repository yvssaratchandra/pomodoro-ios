import XCTest
import SwiftData
@testable import Pomodoro

@MainActor final class AppStoreTests: XCTestCase {
    func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: AppDocument.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    func testPersistenceAndInvalidRestoreLeaveHistoryIntact() throws {
        let container = try makeContainer()
        let store = try AppStore(container: container)
        XCTAssertTrue(store.saveProject(Project(name: "Keep me")))
        let original = store.state
        var invalid = AppSnapshot()
        invalid.settings.dailyGoalMinutes = 0
        XCTAssertFalse(store.restore(invalid))
        XCTAssertEqual(store.state, original)
        let reloaded = try AppStore(container: container)
        XCTAssertEqual(reloaded.state.projects.map(\.name), ["Keep me"])
    }

    func testRestoreReplacesAllDataAndRejectsActiveTimer() throws {
        let store = try AppStore(container: makeContainer())
        XCTAssertTrue(store.saveProject(Project(name: "Original")))
        let replacement = AppSnapshot(projects: [Project(name: "Restored")])
        XCTAssertTrue(store.restore(replacement))
        XCTAssertEqual(store.state.projects.map(\.name), ["Restored"])
        let id = store.state.projects[0].id
        XCTAssertTrue(store.update { try TimerEngine.startFocus(&$0, projectID: id, minutes: 10, now: Date()) })
        XCTAssertFalse(store.restore(AppSnapshot()))
        XCTAssertEqual(store.state.activeTimer?.projectID, id)
    }

    func testDurationPreferencesPersistPerProjectAndDefaultEditsResetThem() throws {
        let container = try makeContainer()
        let store = try AppStore(container: container)
        let writing = Project(name: "Writing")
        let study = Project(name: "Study", focusMinutes: 30)
        XCTAssertTrue(store.saveProject(writing))
        XCTAssertTrue(store.saveProject(study))
        XCTAssertTrue(store.rememberFocusDuration(projectID: writing.id, minutes: 40))
        XCTAssertTrue(store.rememberFocusDuration(projectID: study.id, minutes: 15))
        let reloaded = try AppStore(container: container)
        XCTAssertEqual(reloaded.state.projects.map(\.preferredFocusMinutes), [40, 15])

        // Even an editor draft opened before the preference changed must preserve it.
        var renamed = writing
        renamed.name = "Book"
        renamed.status = .suspended
        XCTAssertTrue(reloaded.saveProject(renamed))
        XCTAssertEqual(reloaded.state.projects[0].preferredFocusMinutes, 40)
        renamed.focusMinutes = 35
        XCTAssertTrue(reloaded.saveProject(renamed))
        XCTAssertEqual(reloaded.state.projects[0].preferredFocusMinutes, 35)
        XCTAssertNil(reloaded.state.projects[0].lastFocusMinutes)
        XCTAssertEqual(reloaded.state.projects[1].preferredFocusMinutes, 15)
    }

    func testDurationChangesLeaveRunningTimerIntactAndInvalidChangesDoNotSave() throws {
        let container = try makeContainer()
        let store = try AppStore(container: container)
        let project = Project(name: "Writing")
        XCTAssertTrue(store.saveProject(project))
        XCTAssertTrue(store.update {
            try TimerEngine.startFocus(&$0, projectID: project.id, minutes: 25, now: Date())
        })
        let active = try XCTUnwrap(store.state.activeTimer)
        XCTAssertTrue(store.rememberFocusDuration(projectID: project.id, minutes: 45))
        XCTAssertEqual(store.state.activeTimer, active)
        XCTAssertEqual(store.state.activeTimer?.deadline, active.deadline)
        XCTAssertFalse(store.rememberFocusDuration(projectID: project.id, minutes: 61))
        XCTAssertFalse(store.rememberFocusDuration(projectID: UUID(), minutes: 30))
        let reloaded = try AppStore(container: container)
        XCTAssertEqual(reloaded.state.projects[0].preferredFocusMinutes, 45)
        XCTAssertEqual(reloaded.state.activeTimer, active)
    }
}
