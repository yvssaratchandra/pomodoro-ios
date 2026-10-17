import XCTest
import UserNotifications
@testable import Pomodoro

@MainActor final class LaunchRoutingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let router = AppURLRouter(scheme: .container)

    func testColdQueueWaitsForStoreAndUsesLatestRememberedDurationOnce() throws {
        let project = Project(name: "Writing", lastFocusMinutes: 40)
        let persistence = try RoutePersistence(AppSnapshot(projects: [project]))
        let store = try makeStore(persistence)
        let navigation = AppNavigation(scheme: .container)
        let url = router.url(for: .startFocus(projectID: project.id))
        navigation.receive(url)
        navigation.receive(url)
        XCTAssertNil(store.state.activeTimer)
        XCTAssertEqual(persistence.saves, 0)
        XCTAssertTrue(store.rememberFocusDuration(projectID: project.id, minutes: 35))
        navigation.connect(to: store)
        let timer = try XCTUnwrap(store.state.activeTimer)
        XCTAssertEqual(timer.projectID, project.id)
        XCTAssertEqual(timer.plannedSeconds, 2100)
        XCTAssertNil(timer.intention)
        XCTAssertEqual(navigation.selectedProjectID, project.id)
        XCTAssertEqual(navigation.selectedTab, .focus)
        XCTAssertEqual(persistence.saves, 2)
        navigation.connect(to: store)
        navigation.receive(url)
        XCTAssertEqual(store.state.activeTimer, timer)
        XCTAssertEqual(persistence.saves, 2)
    }

    func testRunningFocusAndBreakAreNeverReplacedByAnotherProjectLink() throws {
        for kind in [TimerKind.focus, .shortBreak, .longBreak] {
            let first = Project(name: "First")
            let second = Project(name: "Second")
            let timer = ActiveTimer(projectID: first.id, kind: kind, startedAt: now,
                                    plannedSeconds: 600, shortBreakMinutes: 5, longBreakMinutes: 15, longBreakInterval: 4)
            let original = AppSnapshot(projects: [first, second], activeTimer: timer)
            let persistence = try RoutePersistence(original)
            let store = try makeStore(persistence)
            let navigation = AppNavigation(scheme: .container)
            navigation.connect(to: store)
            navigation.showSettings()
            navigation.receive(router.url(for: .startFocus(projectID: second.id)))
            XCTAssertEqual(store.state, original)
            XCTAssertEqual(navigation.selectedProjectID, first.id)
            XCTAssertEqual(navigation.selectedTab, .focus)
            XCTAssertTrue(navigation.focusPath.isEmpty)
            XCTAssertEqual(persistence.saves, 0)
        }
    }

    func testInvalidInactiveAndMergedProjectLinksNeverStartSubstitute() throws {
        let ongoing = Project(name: "Other")
        for status in [ProjectStatus.suspended, .completed] {
            let unavailable = Project(name: "Unavailable", status: status)
            let store = try makeStore(RoutePersistence(AppSnapshot(projects: [ongoing, unavailable])))
            let navigation = AppNavigation(scheme: .container)
            navigation.connect(to: store)
            navigation.selectedProjectID = ongoing.id
            navigation.receive(router.url(for: .startFocus(projectID: unavailable.id)))
            XCTAssertNil(store.state.activeTimer)
            XCTAssertEqual(navigation.selectedProjectID, ongoing.id)
            XCTAssertNotNil(navigation.message)
            navigation.receive(router.url(for: .startFocus(projectID: UUID())))
            XCTAssertNil(store.state.activeTimer)
            XCTAssertEqual(navigation.selectedProjectID, ongoing.id)
        }
    }

    func testMalformedURLDoesNotReconcileOrChangeNavigation() throws {
        let project = Project(name: "Writing")
        var snapshot = AppSnapshot(projects: [project])
        try TimerEngine.startFocus(&snapshot, projectID: project.id, minutes: 10, now: now.addingTimeInterval(-1200))
        let persistence = try RoutePersistence(snapshot)
        let store = try makeStore(persistence)
        let navigation = AppNavigation(scheme: .container)
        navigation.connect(to: store)
        navigation.showSettings()
        navigation.receive(try XCTUnwrap(URL(string: "pomodoro://focus?action=delete")))
        XCTAssertEqual(store.state, snapshot)
        XCTAssertEqual(persistence.saves, 0)
        XCTAssertEqual(navigation.selectedTab, .focus)
        XCTAssertEqual(navigation.focusPath, [.settings])
        XCTAssertNotNil(navigation.message)
    }

    func testExpiredTimerIsSavedOnceBeforeStartingCurrentProjectDuration() throws {
        let project = Project(name: "Writing", lastFocusMinutes: 35)
        var snapshot = AppSnapshot(projects: [project])
        snapshot.settings.haptics = false
        try TimerEngine.startFocus(&snapshot, projectID: project.id, minutes: 10, now: now.addingTimeInterval(-1200))
        let oldID = try XCTUnwrap(snapshot.activeTimer?.id)
        let store = try makeStore(RoutePersistence(snapshot))
        let navigation = AppNavigation(scheme: .container)
        navigation.connect(to: store)
        navigation.receive(router.url(for: .startFocus(projectID: project.id)))
        XCTAssertEqual(store.state.sessions.map(\.id), [oldID])
        XCTAssertEqual(store.state.sessions.first?.outcome, .completed)
        XCTAssertNotEqual(store.state.activeTimer?.id, oldID)
        XCTAssertEqual(store.state.activeTimer?.plannedSeconds, 2100)
        XCTAssertEqual(store.state.completedInCycle, 1)
        XCTAssertNil(store.state.breakOffer)
    }

    func testFailedReconciliationOrStartNeverReplacesStoredWork() throws {
        let project = Project(name: "Writing")
        for active in [false, true] {
            var snapshot = AppSnapshot(projects: [project])
            if active {
                try TimerEngine.startFocus(&snapshot, projectID: project.id, minutes: 10, now: now.addingTimeInterval(-1200))
            }
            let persistence = try RoutePersistence(snapshot)
            persistence.failSave = true
            let store = try makeStore(persistence)
            let navigation = AppNavigation(scheme: .container)
            navigation.connect(to: store)
            navigation.receive(router.url(for: .startFocus(projectID: project.id)))
            XCTAssertEqual(store.state, snapshot)
            XCTAssertEqual(try BackupService.decode(persistence.payload, forBackup: false), snapshot)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testOrdinaryLaunchAndNavigationOnlyRoutesDoNotStartTimers() throws {
        let project = Project(name: "Writing")
        let persistence = try RoutePersistence(AppSnapshot(projects: [project]))
        let store = try makeStore(persistence)
        let navigation = AppNavigation(scheme: .container)
        navigation.connect(to: store)
        XCTAssertNil(store.state.activeTimer)
        navigation.receive(router.url(for: .timer))
        XCTAssertFalse(navigation.showingProjectCreation)
        navigation.receive(router.url(for: .newProject))
        XCTAssertEqual(navigation.selectedTab, .focus)
        XCTAssertTrue(navigation.showingProjectCreation)
        XCTAssertNil(store.state.activeTimer)
        XCTAssertEqual(persistence.saves, 0)
    }
    func testSecondaryNavigationPreservesPreparedNoteAndRunningTimer() throws {
        let project = Project(name: "Writing")
        var snapshot = AppSnapshot(projects: [project])
        try TimerEngine.startFocus(&snapshot, projectID: project.id, minutes: 25, now: now)
        let persistence = try RoutePersistence(snapshot)
        let store = try makeStore(persistence)
        let navigation = AppNavigation(scheme: .container)
        navigation.connect(to: store)
        navigation.selectedProjectID = project.id
        navigation.sessionNoteDrafts[project.id] = "Revise introduction"
        navigation.showProjects()
        XCTAssertEqual(navigation.focusPath, [.projects])
        navigation.showSettings()
        XCTAssertEqual(navigation.focusPath, [.settings])
        navigation.thoughtFilter = .done
        navigation.thoughtSearch = "old search"
        navigation.showThoughts(projectID: project.id)
        XCTAssertEqual(navigation.selectedTab, .thoughts)
        XCTAssertEqual(navigation.thoughtFilter, .open)
        XCTAssertEqual(navigation.thoughtProjectFilter, .project(project.id))
        XCTAssertTrue(navigation.thoughtSearch.isEmpty)
        navigation.showFocus()
        XCTAssertEqual(navigation.selectedTab, .focus)
        XCTAssertTrue(navigation.focusPath.isEmpty)
        XCTAssertEqual(navigation.selectedProjectID, project.id)
        XCTAssertEqual(navigation.sessionNoteDrafts[project.id], "Revise introduction")
        XCTAssertEqual(store.state, snapshot)
        XCTAssertEqual(persistence.saves, 0)
    }

    private func makeStore(_ persistence: RoutePersistence) throws -> AppStore {
        let date = now
        return try AppStore(persistence: persistence, now: { date }, notificationCenter: RouteNotificationCenter())
    }
}

@MainActor private struct RouteNotificationCenter: TimerNotificationCenter {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool { false }
    func add(_ request: UNNotificationRequest) async throws {}
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    func removeAllPendingNotificationRequests() {}
}

@MainActor private final class RoutePersistence: SnapshotPersistence {
    var payload: Data
    var saves = 0
    var failSave = false

    init(_ state: AppSnapshot) throws { payload = try BackupService.encode(state, forBackup: false) }
    func load() throws -> Data? { payload }
    func save(_ payload: Data) throws {
        if failSave { throw AppError.invalid("Save failed") }
        self.payload = payload
        saves += 1
    }
}
