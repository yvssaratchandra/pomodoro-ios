import XCTest
import SwiftData
import UserNotifications
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

    func testDiscardAndHistoryDeletionPersist() throws {
        let container = try makeContainer()
        let store = try AppStore(container: container)
        let project = Project(name: "Writing")
        XCTAssertTrue(store.saveProject(project))
        let start = Date().addingTimeInterval(-1200)
        XCTAssertTrue(store.update {
            try TimerEngine.startFocus(&$0, projectID: project.id, minutes: 10, now: start)
            TimerEngine.finish(&$0, now: start.addingTimeInterval(600))
            try TimerEngine.startFocus(&$0, projectID: project.id, minutes: 10, now: Date())
        })
        let sessionID = try XCTUnwrap(store.state.sessions.first?.id)
        store.discardFocus(timerID: try XCTUnwrap(store.state.activeTimer?.id))
        let reloaded = try AppStore(container: container)
        XCTAssertNil(reloaded.state.activeTimer)
        XCTAssertEqual(reloaded.state.sessions.map(\.id), [sessionID])
        XCTAssertTrue(reloaded.deleteSession(sessionID))
        let afterDeletion = try AppStore(container: container)
        XCTAssertTrue(afterDeletion.state.sessions.isEmpty)
        XCTAssertEqual(afterDeletion.state.completedInCycle, 1)
        XCTAssertEqual(Statistics.total(afterDeletion.state, now: Date()), 0)
    }

    func testFailedInitialSaveAndInvalidStoredDataDoNotPublishOrReplaceData() throws {
        let persistence = MemorySnapshotPersistence()
        persistence.failSave = true
        let publisher = RecordingSnapshotPublisher()
        let activities = RecordingLiveActivityManager()
        let notifications = RecordingNotificationCenter()
        XCTAssertThrowsError(try AppStore(persistence: persistence, publisher: publisher,
                                         liveActivities: activities, notificationCenter: notifications))
        XCTAssertNil(persistence.payload)
        XCTAssertTrue(publisher.states.isEmpty)
        XCTAssertTrue(activities.states.isEmpty)
        XCTAssertEqual(notifications.effectCount, 0)

        let original = Data("not a snapshot".utf8)
        persistence.payload = original
        persistence.failSave = false
        let saves = persistence.saveAttempts
        XCTAssertThrowsError(try AppStore(persistence: persistence, publisher: publisher,
                                         liveActivities: activities, notificationCenter: notifications))
        XCTAssertEqual(persistence.payload, original)
        XCTAssertEqual(persistence.saveAttempts, saves)
        XCTAssertTrue(publisher.states.isEmpty)
    }

    func testFailedStartDoesNotPublishOrScheduleAndSuccessfulSavePublishesDurableState() async throws {
        let project = Project(name: "Writing")
        let snapshot = AppSnapshot(projects: [project])
        let persistence = MemorySnapshotPersistence(payload: try BackupService.encode(snapshot))
        let publisher = RecordingSnapshotPublisher()
        let activities = RecordingLiveActivityManager()
        let notifications = RecordingNotificationCenter()
        let loaded = expectation(description: "Initial activity synchronization")
        activities.onSynchronize = { _ in loaded.fulfill() }
        let store = try AppStore(persistence: persistence, publisher: publisher,
                                 liveActivities: activities, notificationCenter: notifications)
        await fulfillment(of: [loaded], timeout: 2)
        activities.onSynchronize = nil
        publisher.states.removeAll()
        activities.states.removeAll()
        let originalBytes = persistence.payload

        persistence.failSave = true
        store.startFocus(projectID: project.id, minutes: 25)
        await Task.yield()
        XCTAssertEqual(store.state, snapshot)
        XCTAssertEqual(persistence.payload, originalBytes)
        XCTAssertTrue(publisher.states.isEmpty)
        XCTAssertTrue(activities.states.isEmpty)
        XCTAssertEqual(notifications.effectCount, 0)

        persistence.failSave = false
        let updated = expectation(description: "Committed activity synchronization")
        activities.onSynchronize = { _ in updated.fulfill() }
        var publishedAfterSave = false
        var publishedAfterStateUpdate = false
        publisher.onPublish = { state in
            if let payload = persistence.payload {
                publishedAfterSave = (try? BackupService.decode(payload, forBackup: false)) == state
            }
            publishedAfterStateUpdate = store.state == state
        }
        XCTAssertTrue(store.rememberFocusDuration(projectID: project.id, minutes: 40))
        await fulfillment(of: [updated], timeout: 2)
        XCTAssertTrue(publishedAfterSave)
        XCTAssertTrue(publishedAfterStateUpdate)
        XCTAssertEqual(publisher.states, [store.state])
        XCTAssertEqual(activities.states, [store.state])
        XCTAssertEqual(try AppStore(persistence: persistence).state, store.state)
    }

    func testFailedEndDiscardAndRestoreLeaveTimerAndNotificationsIntact() throws {
        let project = Project(name: "Writing")
        var snapshot = AppSnapshot(projects: [project])
        try TimerEngine.startFocus(&snapshot, projectID: project.id, minutes: 25, now: Date())
        let persistence = MemorySnapshotPersistence(payload: try BackupService.encode(snapshot, forBackup: false))
        let publisher = RecordingSnapshotPublisher()
        let notifications = RecordingNotificationCenter()
        let deadline = try XCTUnwrap(snapshot.activeTimer?.deadline)
        let store = try AppStore(persistence: persistence, now: { deadline }, publisher: publisher,
                                 notificationCenter: notifications)
        publisher.states.removeAll()
        persistence.failSave = true
        store.endTimer()
        store.discardFocus(timerID: try XCTUnwrap(snapshot.activeTimer?.id))
        store.reconcile()
        XCTAssertEqual(store.state, snapshot)
        XCTAssertEqual(try BackupService.decode(XCTUnwrap(persistence.payload), forBackup: false), snapshot)
        XCTAssertTrue(publisher.states.isEmpty)
        XCTAssertEqual(notifications.effectCount, 0)

        let idle = AppSnapshot(projects: [project])
        let idlePersistence = MemorySnapshotPersistence(payload: try BackupService.encode(idle))
        let idleStore = try AppStore(persistence: idlePersistence, notificationCenter: notifications)
        idlePersistence.failSave = true
        XCTAssertFalse(idleStore.restore(AppSnapshot()))
        XCTAssertEqual(idleStore.state, idle)
        XCTAssertEqual(notifications.effectCount, 0)
    }

    func testInjectedClockControlsFocusReconciliationBreakAndInterruptedWork() throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000.125)
        var date = start
        let project = Project(name: "Writing")
        var snapshot = AppSnapshot(projects: [project])
        snapshot.settings.haptics = false
        let persistence = MemorySnapshotPersistence(payload: try BackupService.encode(snapshot))
        let publisher = RecordingSnapshotPublisher()
        let store = try AppStore(persistence: persistence, now: { date }, publisher: publisher,
                                 notificationCenter: RecordingNotificationCenter())
        store.startFocus(projectID: project.id, minutes: 10)
        XCTAssertEqual(store.state.activeTimer?.startedAt, start)
        date = start.addingTimeInterval(599)
        store.reconcile()
        XCTAssertNotNil(store.state.activeTimer)
        XCTAssertTrue(store.state.sessions.isEmpty)
        date = start.addingTimeInterval(600)
        store.reconcile()
        XCTAssertNil(store.state.activeTimer)
        XCTAssertEqual(store.state.sessions.first?.endedAt, date)
        XCTAssertEqual(store.state.sessions.first?.outcome, .completed)
        store.startBreak()
        XCTAssertEqual(store.state.activeTimer?.startedAt, date)
        XCTAssertEqual(store.state.activeTimer?.kind, .shortBreak)
        date = date.addingTimeInterval(60)
        store.endTimer()
        store.startFocus(projectID: project.id, minutes: 10)
        let secondStart = date
        date = date.addingTimeInterval(42.25)
        store.endTimer()
        XCTAssertEqual(store.state.sessions.last?.startedAt, secondStart)
        XCTAssertEqual(store.state.sessions.last?.duration, 42.25)
        XCTAssertEqual(store.state.sessions.last?.outcome, .interrupted)
        XCTAssertEqual(publisher.dates.last, date)
    }

    func testProjectionFailureKeepsSavedWorkAndActivationCanRetry() throws {
        let persistence = MemorySnapshotPersistence()
        let publisher = RecordingSnapshotPublisher()
        let store = try AppStore(persistence: persistence, publisher: publisher)
        publisher.failPublish = true
        XCTAssertTrue(store.saveProject(Project(name: "Saved despite display failure")))
        XCTAssertEqual(try AppStore(persistence: persistence).state, store.state)
        XCTAssertNotNil(store.errorMessage)
        let saves = persistence.saveAttempts
        publisher.failPublish = false
        store.refreshExternalSurfaces()
        XCTAssertEqual(publisher.states.last, store.state)
        XCTAssertEqual(persistence.saveAttempts, saves)
    }

    func testActivitySynchronizationIsSerializedAndSkipsSupersededCommits() async throws {
        let activities = RecordingLiveActivityManager()
        let loaded = expectation(description: "Initial activity synchronization")
        activities.onSynchronize = { _ in loaded.fulfill() }
        let store = try AppStore(persistence: MemorySnapshotPersistence(), liveActivities: activities)
        await fulfillment(of: [loaded], timeout: 2)
        activities.states.removeAll()
        let started = expectation(description: "First commit synchronization started")
        activities.holdNext = true
        activities.onSynchronize = { _ in started.fulfill() }
        XCTAssertTrue(store.saveProject(Project(name: "First")))
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(store.saveProject(Project(name: "Superseded")))
        XCTAssertTrue(store.saveProject(Project(name: "Latest")))
        let finished = expectation(description: "Latest commit synchronized")
        activities.onSynchronize = { _ in finished.fulfill() }
        activities.release()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(activities.states.count, 2)
        XCTAssertEqual(activities.states.first?.projects.map(\.name), ["First"])
        XCTAssertEqual(activities.states.last, store.state)
    }

    func testSwiftDataRollbackPreservesExistingBytesAndAllowsRetry() throws {
        let container = try makeContainer()
        let original = try BackupService.encode(AppSnapshot(projects: [Project(name: "Original")]))
        try SwiftDataSnapshotPersistence(container: container).save(original)
        var failSave = true
        let persistence = try SwiftDataSnapshotPersistence(container: container, saveContext: { context in
            if failSave { throw TestStoreError.save }
            try context.save()
        })
        let replacement = try BackupService.encode(AppSnapshot(projects: [Project(name: "Replacement")]))
        XCTAssertThrowsError(try persistence.save(replacement))
        XCTAssertEqual(try persistence.load(), original)
        XCTAssertEqual(try SwiftDataSnapshotPersistence(container: container).load(), original)
        failSave = false
        try persistence.save(replacement)
        XCTAssertEqual(try SwiftDataSnapshotPersistence(container: container).load(), replacement)
    }

    func testSwiftDataFailedInitialInsertCanRetryWithoutDuplicateDocuments() throws {
        let container = try makeContainer()
        var failSave = true
        let persistence = try SwiftDataSnapshotPersistence(container: container, saveContext: { context in
            if failSave { throw TestStoreError.save }
            try context.save()
        })
        XCTAssertThrowsError(try AppStore(persistence: persistence))
        XCTAssertNil(try persistence.load())
        XCTAssertNil(try SwiftDataSnapshotPersistence(container: container).load())
        failSave = false
        let store = try AppStore(persistence: persistence)
        XCTAssertEqual(try AppStore(container: container).state, store.state)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppDocument>()), 1)
    }

    func testStartupMigratesStoredV1OnceBeforePublishingWithoutChangingRunningTimer() throws {
        let original = try MigrationFixtures.data("v1-running")
        let persistence = MemorySnapshotPersistence(payload: original)
        let publisher = RecordingSnapshotPublisher()
        var publishedAfterMigrationSave = false
        publisher.onPublish = { state in
            if let payload = persistence.payload {
                publishedAfterMigrationSave = persistence.saveAttempts == 1 && payload != original
                    && (try? BackupService.decode(payload, forBackup: false)) == state
            }
        }
        let store = try AppStore(persistence: persistence, publisher: publisher,
                                 notificationCenter: RecordingNotificationCenter())
        XCTAssertTrue(publishedAfterMigrationSave)
        XCTAssertEqual(publisher.states, [store.state])
        XCTAssertEqual(store.state.schemaVersion, AppSnapshot.currentSchemaVersion)
        XCTAssertEqual(store.state.activeTimer?.id, UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        XCTAssertEqual(store.state.activeTimer?.deadline, Date(timeIntervalSinceReferenceDate: 770004500.875))
        XCTAssertEqual(store.state.completedInCycle, 1)
        XCTAssertEqual(store.state.sessions.map(\.duration), [600, 59.75])
        XCTAssertEqual(persistence.saveAttempts, 1)
        XCTAssertEqual(try AppStore(persistence: persistence).state, store.state)
        XCTAssertEqual(persistence.saveAttempts, 1)
    }

    func testFailedMigrationSaveKeepsOriginalBytesAndPublishesNothing() throws {
        let original = try MigrationFixtures.data("v1-running")
        let persistence = MemorySnapshotPersistence(payload: original)
        persistence.failSave = true
        let publisher = RecordingSnapshotPublisher()
        let activities = RecordingLiveActivityManager()
        let notifications = RecordingNotificationCenter()
        XCTAssertThrowsError(try AppStore(persistence: persistence, publisher: publisher,
                                         liveActivities: activities, notificationCenter: notifications))
        XCTAssertEqual(persistence.payload, original)
        XCTAssertEqual(persistence.saveAttempts, 1)
        XCTAssertTrue(publisher.states.isEmpty)
        XCTAssertTrue(activities.states.isEmpty)
        XCTAssertEqual(notifications.effectCount, 0)
        persistence.failSave = false
        let store = try AppStore(persistence: persistence)
        XCTAssertEqual(store.state.schemaVersion, AppSnapshot.currentSchemaVersion)
        XCTAssertEqual(persistence.saveAttempts, 2)
    }

    func testInvalidLegacyAndFutureDocumentsAreNotSavedOrReplaced() throws {
        let original = try MigrationFixtures.data("v1-history")
        var malformed = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        malformed.removeValue(forKey: "sessions")
        var future = AppSnapshot()
        future.schemaVersion = 999
        let inputs = [try JSONSerialization.data(withJSONObject: malformed), try JSONEncoder().encode(future)]
        for data in inputs {
            let persistence = MemorySnapshotPersistence(payload: data)
            let publisher = RecordingSnapshotPublisher()
            XCTAssertThrowsError(try AppStore(persistence: persistence, publisher: publisher))
            XCTAssertEqual(persistence.payload, data)
            XCTAssertEqual(persistence.saveAttempts, 0)
            XCTAssertTrue(publisher.states.isEmpty)
        }
    }

    func testSwiftDataMigrationFailurePreservesV1DocumentThenRetriesAtomically() throws {
        let container = try makeContainer()
        let original = try MigrationFixtures.data("v1-running")
        try SwiftDataSnapshotPersistence(container: container).save(original)
        let failed = try SwiftDataSnapshotPersistence(container: container, saveContext: { _ in
            throw TestStoreError.save
        })
        XCTAssertThrowsError(try AppStore(persistence: failed))
        XCTAssertEqual(try failed.load(), original)
        XCTAssertEqual(try SwiftDataSnapshotPersistence(container: container).load(), original)
        let store = try AppStore(container: container)
        XCTAssertEqual(store.state.schemaVersion, AppSnapshot.currentSchemaVersion)
        XCTAssertEqual(try AppStore(container: container).state, store.state)
        let payload = try XCTUnwrap(SwiftDataSnapshotPersistence(container: container).load())
        XCTAssertFalse(try BackupService.decodeWithMigration(payload, forBackup: false).didMigrate)
    }
    func testGroupedUndoIsAtomicAndCanRetryAfterSaveFailure() throws {
        var tick: TimeInterval = 100
        let project = Project(name: "Writing")
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let sessions = (0..<2).map { index in
            FocusSession(id: UUID(), projectID: project.id, startedAt: start.addingTimeInterval(Double(index * 1200)),
                         endedAt: start.addingTimeInterval(Double(index * 1200 + 600)), plannedSeconds: 600, outcome: .completed,
                         intention: "Keep the exact record")
        }
        let snapshot = AppSnapshot(projects: [project], sessions: sessions)
        let persistence = MemorySnapshotPersistence(payload: try BackupService.encode(snapshot))
        let store = try AppStore(persistence: persistence, uptime: { tick }, voiceOver: { false })
        persistence.failSave = true
        XCTAssertFalse(store.deleteSession(sessions[0].id))
        XCTAssertNil(store.pendingDeletion)
        persistence.failSave = false
        XCTAssertTrue(store.deleteSession(sessions[0].id))
        tick = 105
        XCTAssertTrue(store.deleteSession(sessions[1].id))
        XCTAssertEqual(store.pendingDeletion?.sessions.count, 2)
        XCTAssertEqual(store.pendingDeletion?.expiresAt, 115)
        persistence.failSave = true
        XCTAssertFalse(store.undoDeletion())
        XCTAssertTrue(store.state.sessions.isEmpty)
        XCTAssertEqual(store.pendingDeletion?.sessions.count, 2)
        persistence.failSave = false
        XCTAssertTrue(store.undoDeletion())
        XCTAssertEqual(store.state.sessions, sessions)
        XCTAssertNil(store.pendingDeletion)
        XCTAssertEqual(try AppStore(persistence: persistence).state, store.state)
    }

    func testUndoUsesMonotonicExpiryAndRejectsConflictingHistoryAsOneGroup() throws {
        var tick: TimeInterval = 0
        let project = Project(name: "Writing")
        let date = Date()
        let session = FocusSession(id: UUID(), projectID: project.id, startedAt: date, endedAt: date,
                                   plannedSeconds: 600, outcome: .interrupted)
        let persistence = MemorySnapshotPersistence(payload: try BackupService.encode(AppSnapshot(projects: [project], sessions: [session])))
        let store = try AppStore(persistence: persistence, uptime: { tick }, voiceOver: { true })
        XCTAssertTrue(store.deleteSession(session.id))
        tick = 29
        store.expireUndo()
        XCTAssertNotNil(store.pendingDeletion)
        XCTAssertTrue(store.update { $0.sessions.append(session) })
        XCTAssertFalse(store.undoDeletion())
        XCTAssertEqual(store.state.sessions, [session])
        tick = 30
        XCTAssertFalse(store.undoDeletion())
        XCTAssertNil(store.pendingDeletion)
    }

    func testIntentionThoughtAndBreadcrumbPersistAcrossSessionDeletionAndUndo() throws {
        var date = Date()
        let project = Project(name: "Writing")
        let persistence = MemorySnapshotPersistence(payload: try BackupService.encode(AppSnapshot(projects: [project])))
        let store = try AppStore(persistence: persistence, now: { date }, notificationCenter: RecordingNotificationCenter())
        XCTAssertTrue(store.startFocus(projectID: project.id, minutes: 10, intention: "Draft introduction"))
        let timer = try XCTUnwrap(store.state.activeTimer)
        let context = ThoughtCaptureContext(projectID: project.id, originSessionID: timer.id)
        XCTAssertTrue(store.captureThought(context: context, text: "Find the source later"))
        date = date.addingTimeInterval(90)
        store.endTimer()
        XCTAssertTrue(store.saveNextStep(sessionID: timer.id, text: "Continue with methods", promote: true))
        XCTAssertTrue(store.editIntention(id: timer.id, active: false, text: "Revise introduction"))
        let thought = try XCTUnwrap(store.state.thoughts.first)
        XCTAssertTrue(store.setThoughtCompleted(id: thought.id, completed: true))
        XCTAssertTrue(store.deleteSession(timer.id))
        XCTAssertEqual(store.state.thoughts.first?.text, thought.text)
        XCTAssertNotNil(store.state.thoughts.first?.completedAt)
        XCTAssertEqual(store.state.projects.first?.breadcrumb?.text, "Continue with methods")
        XCTAssertTrue(store.undoDeletion())
        XCTAssertEqual(store.state.sessions.first?.intention, "Revise introduction")
        XCTAssertEqual(store.state.sessions.first?.nextStep, "Continue with methods")
        XCTAssertTrue(store.setThoughtCompleted(id: thought.id, completed: false))
        XCTAssertNil(store.state.thoughts.first?.completedAt)
        let backup = try BackupService.decode(BackupService.encode(store.state))
        XCTAssertEqual(backup, store.state)
        XCTAssertTrue(store.restore(backup))
        XCTAssertNil(store.lastFinishedSessionID)
    }

    func testMixedDeletionUndoRestoresExactThoughtsAndSessionsAtomically() throws {
        let project = Project(name: "Writing")
        let date = Date()
        let session = FocusSession(id: UUID(), projectID: project.id, startedAt: date, endedAt: date,
                                   plannedSeconds: 600, outcome: .interrupted, intention: "Draft")
        let thought = CapturedThought(projectID: project.id, originSessionID: session.id,
                                      createdAt: date, text: "Find source", completedAt: date)
        let original = AppSnapshot(projects: [project], sessions: [session], thoughts: [thought])
        let persistence = MemorySnapshotPersistence(payload: try BackupService.encode(original))
        let store = try AppStore(persistence: persistence)
        XCTAssertTrue(store.deleteSession(session.id))
        XCTAssertTrue(store.deleteThought(id: thought.id))
        XCTAssertEqual(store.pendingDeletion?.count, 2)
        XCTAssertEqual(store.pendingDeletion?.message, "2 items deleted")
        persistence.failSave = true
        XCTAssertFalse(store.undoDeletion())
        XCTAssertTrue(store.state.sessions.isEmpty)
        XCTAssertTrue(store.state.thoughts.isEmpty)
        XCTAssertEqual(store.pendingDeletion?.count, 2)
        persistence.failSave = false
        XCTAssertTrue(store.undoDeletion())
        XCTAssertEqual(store.state, original)
        XCTAssertNil(store.pendingDeletion)
    }

    func testEmptyProjectDeletionProtectsContentAndPendingUndo() throws {
        let project = Project(name: "Temporary")
        let date = Date()
        let thought = CapturedThought(projectID: project.id, createdAt: date, text: "Keep")
        let persistence = MemorySnapshotPersistence(payload: try BackupService.encode(AppSnapshot(projects: [project], thoughts: [thought])))
        let store = try AppStore(persistence: persistence)
        XCTAssertFalse(store.canDeleteProject(id: project.id))
        XCTAssertFalse(store.deleteEmptyProject(id: project.id))
        XCTAssertTrue(store.deleteThought(id: thought.id))
        XCTAssertFalse(store.canDeleteProject(id: project.id))
        let empty = Project(name: "Unused")
        XCTAssertTrue(store.saveProject(empty))
        XCTAssertTrue(store.deleteEmptyProject(id: empty.id))
        XCTAssertEqual(store.pendingDeletion?.thoughts, [thought])
        store.dismissUndo()
        XCTAssertTrue(store.canDeleteProject(id: project.id))
        XCTAssertTrue(store.deleteEmptyProject(id: project.id))
        XCTAssertTrue(store.state.projects.isEmpty)
    }

    func testAudioEditsPersistOnActiveTimerWithoutChangingItsDeadline() throws {
        let project = Project(name: "Writing")
        let persistence = MemorySnapshotPersistence(payload: try BackupService.encode(AppSnapshot(projects: [project])))
        let store = try AppStore(persistence: persistence, notificationCenter: RecordingNotificationCenter())
        XCTAssertTrue(store.startFocus(projectID: project.id, minutes: 25))
        let timer = try XCTUnwrap(store.state.activeTimer)
        XCTAssertTrue(store.updateCompletionAudio(enabled: false))
        XCTAssertEqual(store.state.activeTimer?.completionSound, .silent)
        XCTAssertEqual(store.state.activeTimer?.deadline, timer.deadline)
        XCTAssertEqual(store.state.activeTimer?.id, timer.id)
        persistence.failSave = true
        XCTAssertFalse(store.updateCompletionAudio(enabled: true))
        XCTAssertFalse(store.state.settings.notificationSound)
        XCTAssertEqual(store.state.activeTimer?.completionSound, .silent)
        persistence.failSave = false
        XCTAssertTrue(store.updateCompletionAudio(enabled: true))
        XCTAssertEqual(store.state.activeTimer?.completionSound, .systemDefault)
        XCTAssertEqual(try AppStore(persistence: persistence).state.activeTimer, store.state.activeTimer)
    }

    func testUnassignedThoughtDeletionCanBeUndoneWithoutProjects() throws {
        let persistence = MemorySnapshotPersistence()
        let store = try AppStore(persistence: persistence)
        XCTAssertTrue(store.captureThought(context: ThoughtCaptureContext(projectID: nil, originSessionID: nil), text: "Remember"))
        let thought = try XCTUnwrap(store.state.thoughts.first)
        XCTAssertTrue(store.deleteThought(id: thought.id))
        XCTAssertTrue(store.undoDeletion())
        XCTAssertEqual(store.state.thoughts, [thought])
        XCTAssertTrue(store.state.projects.isEmpty)
    }

}

private enum TestStoreError: Error { case save, publish }

@MainActor private final class MemorySnapshotPersistence: SnapshotPersistence {
    var payload: Data?
    var failSave = false
    var saveAttempts = 0

    init(payload: Data? = nil) { self.payload = payload }
    func load() throws -> Data? { payload }
    func save(_ payload: Data) throws {
        saveAttempts += 1
        if failSave { throw TestStoreError.save }
        self.payload = payload
    }
}

@MainActor private final class RecordingSnapshotPublisher: SnapshotPublishing {
    var states: [AppSnapshot] = []
    var dates: [Date] = []
    var failPublish = false
    var onPublish: ((AppSnapshot) -> Void)?

    func publish(_ state: AppSnapshot, now: Date) throws {
        if failPublish { throw TestStoreError.publish }
        states.append(state)
        dates.append(now)
        onPublish?(state)
    }
}

@MainActor private final class RecordingLiveActivityManager: LiveActivityManaging {
    var states: [AppSnapshot] = []
    var onSynchronize: ((AppSnapshot) -> Void)?
    var holdNext = false
    private var continuation: CheckedContinuation<Void, Never>?

    func synchronize(with state: AppSnapshot) async {
        states.append(state)
        onSynchronize?(state)
        if holdNext {
            holdNext = false
            await withCheckedContinuation { continuation = $0 }
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor private final class RecordingNotificationCenter: TimerNotificationCenter {
    private(set) var effectCount = 0

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        effectCount += 1
        return false
    }

    func add(_ request: UNNotificationRequest) async throws { effectCount += 1 }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) { effectCount += 1 }
    func removeAllPendingNotificationRequests() { effectCount += 1 }
}
