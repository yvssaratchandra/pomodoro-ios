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
}
