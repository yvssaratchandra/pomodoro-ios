import XCTest
#if SWIFT_PACKAGE
@testable import PomodoroCore
#else
@testable import Pomodoro
#endif

final class ExternalSurfacesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000.125)
    private let projectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    func testProjectionIncludesOnlyOngoingProjectsWithRememberedDurations() {
        let writing = Project(name: "Writing", focusMinutes: 25, lastFocusMinutes: 40)
        let study = Project(name: "日本語 📚", focusMinutes: 30)
        let suspended = Project(name: "On hold", status: .suspended)
        let completed = Project(name: "Finished", status: .completed)
        let state = AppSnapshot(projects: [writing, suspended, study, completed])
        let snapshot = WidgetSnapshot(state: state, now: now)
        XCTAssertEqual(snapshot.formatVersion, WidgetSnapshot.currentFormatVersion)
        XCTAssertEqual(snapshot.formatVersion, 2)
        XCTAssertEqual(state.schemaVersion, AppSnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.generatedAt, now)
        XCTAssertEqual(snapshot.projects.map(\.id), [writing.id, study.id])
        XCTAssertEqual(snapshot.projects.map(\.name), ["Writing", "日本語 📚"])
        XCTAssertEqual(snapshot.projects.map(\.preferredFocusMinutes), [40, 30])
        XCTAssertNil(snapshot.activeTimer)
    }

    func testProjectionKeepsActiveMetadataAndExportsOnlyPermittedFields() throws {
        var state = try BackupService.decode(MigrationFixtures.data("v1-running"), forBackup: false)
        state.activeTimer?.intention = "Private current intention"
        state.sessions[0].intention = "Private historical intention"
        state.settings.showProjectNameOnLockScreen = true
        state.settings.showIntentionOnLockScreen = true
        let snapshot = WidgetSnapshot(state: state, now: now)
        let timer = try XCTUnwrap(state.activeTimer)
        XCTAssertEqual(snapshot.activeTimer?.id, timer.id)
        XCTAssertEqual(snapshot.activeTimer?.kind, .focus)
        XCTAssertEqual(snapshot.activeTimer?.projectName, "Writing")
        XCTAssertEqual(snapshot.activeTimer?.startedAt, timer.startedAt)
        XCTAssertEqual(snapshot.activeTimer?.deadline, timer.deadline)

        let data = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: data), snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), Set(["formatVersion", "generatedAt", "projects", "activeTimer"]))
        let projects = try XCTUnwrap(json["projects"] as? [[String: Any]])
        XCTAssertEqual(Set(projects[0].keys), Set(["id", "name", "preferredFocusMinutes"]))
        let active = try XCTUnwrap(json["activeTimer"] as? [String: Any])
        XCTAssertEqual(Set(active.keys), Set(["id", "kind", "projectName", "startedAt", "deadline"]))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("Private"))
        XCTAssertFalse(text.contains(state.sessions[0].id.uuidString))
    }

    func testBreakProjectionIncludesItsProjectEvenWhenProjectIsArchived() throws {
        for kind in [TimerKind.shortBreak, .longBreak] {
            let project = Project(name: "Archived project", status: .completed)
            let timer = ActiveTimer(projectID: project.id, kind: kind, startedAt: now,
                                    plannedSeconds: 300, shortBreakMinutes: 0,
                                    longBreakMinutes: 0, longBreakInterval: 4)
            let state = AppSnapshot(projects: [project], activeTimer: timer)
            let snapshot = WidgetSnapshot(state: state, now: now)
            XCTAssertTrue(snapshot.projects.isEmpty)
            XCTAssertEqual(snapshot.activeTimer?.kind, kind)
            XCTAssertEqual(snapshot.activeTimer?.projectName, project.name)
            XCTAssertEqual(snapshot.activeTimer?.deadline, timer.deadline)
            XCTAssertEqual(snapshot.route(for: nil), .timer)
        }
    }

    func testIdleWidgetRoutesOnlyStartAnExplicitAvailableProject() {
        let project = Project(name: "Writing")
        let snapshot = WidgetSnapshot(state: AppSnapshot(projects: [project]), now: now)
        XCTAssertEqual(snapshot.route(for: project.id), .startFocus(projectID: project.id))
        XCTAssertEqual(snapshot.route(for: nil), .timer)
        XCTAssertEqual(snapshot.route(for: UUID()), .timer)
        let empty = WidgetSnapshot(state: AppSnapshot(), now: now)
        XCTAssertEqual(empty.route(for: nil), .newProject)
        XCTAssertEqual(empty.route(for: project.id), .newProject)
    }

    func testMissingOrInactiveSelectionsNeverStartAnotherProject() {
        let ongoing = Project(name: "Other project")
        for status in [ProjectStatus.suspended, .completed] {
            let selected = Project(name: "Unavailable", status: status)
            let state = AppSnapshot(projects: [selected, ongoing])
            XCTAssertEqual(WidgetSnapshot(state: state, now: now).route(for: selected.id), .timer)
        }
        let merged = WidgetSnapshot(state: AppSnapshot(projects: [ongoing]), now: now)
        XCTAssertEqual(merged.route(for: projectID), .timer)
    }

    func testRunningAndExpiredSnapshotsOnlyOpenExistingTimerWithoutMutatingState() throws {
        for kind in [TimerKind.focus, .shortBreak, .longBreak] {
            let project = Project(name: "Writing")
            let other = Project(name: "Other project")
            let timer = ActiveTimer(projectID: project.id, kind: kind, startedAt: now,
                                    plannedSeconds: 600, shortBreakMinutes: 5,
                                    longBreakMinutes: 15, longBreakInterval: 4)
            let state = AppSnapshot(projects: [project, other], activeTimer: timer)
            let original = state
            for time in [now, timer.deadline, timer.deadline.addingTimeInterval(3600)] {
                let snapshot = WidgetSnapshot(state: state, now: time)
                XCTAssertEqual(snapshot.generatedAt, time)
                XCTAssertEqual(snapshot.activeTimer?.id, timer.id)
                XCTAssertEqual(snapshot.activeTimer?.deadline, timer.deadline)
                XCTAssertEqual(snapshot.route(for: project.id), .timer)
                XCTAssertEqual(snapshot.route(for: other.id), .timer)
                XCTAssertEqual(snapshot.route(for: nil), .timer)
                for scheme in AppURLScheme.allCases {
                    let router = AppURLRouter(scheme: scheme)
                    XCTAssertEqual(router.parse(router.url(for: snapshot.route(for: project.id))), .timer)
                }
            }
            XCTAssertEqual(state, original)
        }
    }

    func testRoutesRoundTripForEachInstallationScheme() {
        let routes: [AppRoute] = [.startFocus(projectID: projectID), .timer, .newProject]
        for scheme in AppURLScheme.allCases {
            let router = AppURLRouter(scheme: scheme)
            for route in routes {
                let url = router.url(for: route)
                XCTAssertEqual(url.scheme, scheme.rawValue)
                XCTAssertEqual(router.parse(url), route)
            }
            XCTAssertEqual(router.url(for: .startFocus(projectID: projectID)).absoluteString,
                           "\(scheme.rawValue)://focus?project=\(projectID.uuidString)&action=start")
            XCTAssertEqual(router.url(for: .timer).absoluteString, "\(scheme.rawValue)://timer")
            XCTAssertEqual(router.url(for: .newProject).absoluteString, "\(scheme.rawValue)://projects/new")
        }
    }

    func testParserAllowsReorderedQueryItemsAndCaseInsensitiveSchemeAndHost() throws {
        let router = AppURLRouter(scheme: .container)
        let url = try XCTUnwrap(URL(string: "POMODORO://FOCUS?action=start&project=\(projectID.uuidString.lowercased())"))
        XCTAssertEqual(router.parse(url), .startFocus(projectID: projectID))
        XCTAssertEqual(router.parse(try XCTUnwrap(URL(string: "POMODORO://TIMER"))), .timer)
    }

    func testParserRejectsWrongSchemesUnknownCommandsAndInvalidProjectIDs() throws {
        let invalid = [
            "https://focus?project=\(projectID)&action=start",
            "pomodoro-native://focus?project=\(projectID)&action=start",
            "pomodoro://focus?project=not-a-uuid&action=start",
            "pomodoro://focus?project=&action=start",
            "pomodoro://focus?action=start",
            "pomodoro://focus?project=\(projectID)",
            "pomodoro://focus?project=\(projectID)&action=stop",
            "pomodoro://focus?project=\(projectID)&action=START",
            "pomodoro://focus?project=\(projectID)&action=delete",
            "pomodoro://delete", "pomodoro://restore", "pomodoro://projects",
            "pomodoro://projects/delete", "pomodoro://focus/start",
            "pomodoro:/timer", "pomodoro:timer"
        ]
        let router = AppURLRouter(scheme: .container)
        for text in invalid {
            XCTAssertNil(router.parse(try XCTUnwrap(URL(string: text))), text)
        }
        let native = AppURLRouter(scheme: .native)
        XCTAssertNil(native.parse(AppURLRouter(scheme: .container).url(for: .timer)))
    }

    func testParserRejectsDuplicateAndExtraParametersPathsAndAuthorityComponents() throws {
        let start = "pomodoro://focus?project=\(projectID)&action=start"
        let invalid = [
            start + "&project=\(projectID)", start + "&action=start",
            start + "&duration=10", start + "&intention=Work", start + "&delete=true",
            start + "#timer", start + "#", start + "&unexpected",
            "pomodoro://focus?project=\(projectID)&project=\(projectID)",
            "pomodoro://focus/?project=\(projectID)&action=start",
            "pomodoro://user@focus?project=\(projectID)&action=start",
            "pomodoro://user:password@focus?project=\(projectID)&action=start",
            "pomodoro://focus:123?project=\(projectID)&action=start",
            "pomodoro://timer?", "pomodoro://timer?project=\(projectID)",
            "pomodoro://timer/", "pomodoro://timer/extra", "pomodoro://timer#focus",
            "pomodoro://projects/new?", "pomodoro://projects/new?action=start",
            "pomodoro://projects/new/", "pomodoro://projects/new/extra"
        ]
        let router = AppURLRouter(scheme: .container)
        for text in invalid {
            XCTAssertNil(router.parse(try XCTUnwrap(URL(string: text))), text)
        }
    }
}
