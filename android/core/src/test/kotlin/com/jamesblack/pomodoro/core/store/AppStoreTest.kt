package com.jamesblack.pomodoro.core.store

import com.jamesblack.pomodoro.core.*
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlin.test.*
import java.time.ZoneId

class AppStoreTest {
    private val timestamp = 800000000.0
    private val project = Project(name = "Work", createdAt = timestamp)
    private class Disk(var document: LocalDocument? = null) : SnapshotPersistence {
        var fail = false
        var saves = 0
        override suspend fun load(): LocalDocument? = document
        override suspend fun save(document: LocalDocument) { check(!fail) { "Disk full" }; this.document = document; saves++ }
    }
    @Test fun failedSaveDoesNotPublishOrCallEffects() = runTest {
        val disk = Disk(LocalDocument(snapshot = AppSnapshot(projects = listOf(project))))
        var effects = 0
        val store = AppStore(disk, now = { timestamp }, effects = StoreEffects { effects++ })
        store.initialize(); val initial = store.snapshot; val initialEffects = effects
        disk.fail = true
        assertIs<MutationResult.Failure>(store.execute(AppCommand.StartFocus(project.id, 25)))
        assertEquals(initial, store.snapshot); assertEquals(initialEffects, effects)
    }
    @Test fun duplicateAlarmAndRelaunchCannotReplayCompletion() = runTest {
        var now = timestamp
        val disk = Disk(LocalDocument(snapshot = AppSnapshot(projects = listOf(project))))
        var delivered = 0
        val effects = object : StoreEffects {
            override suspend fun synchronize(document: LocalDocument) {}
            override suspend fun deliverCompletion(ticket: AlarmTicket, snapshot: AppSnapshot) { delivered++ }
        }
        val store = AppStore(disk, now = { now }, effects = effects)
        store.initialize(); store.execute(AppCommand.StartFocus(project.id, 10))
        val timer = store.snapshot.activeTimer!!; now = timer.deadline
        // Foreground reconciliation and receiver may race; both serialize through store.
        store.execute(AppCommand.Reconcile)
        store.execute(AppCommand.AlarmFired(timer.id, timer.deadline))
        store.execute(AppCommand.AlarmFired(timer.id, timer.deadline))
        assertEquals(1, delivered); assertEquals(1, store.snapshot.sessions.size)
        val relaunched = AppStore(disk, now = { now }, effects = effects)
        relaunched.initialize(); relaunched.execute(AppCommand.AlarmFired(timer.id, timer.deadline))
        assertEquals(1, delivered)
    }
    @Test fun recoverySuppressesExpiredAlarmAndSavesCompletedWork() = runTest {
        val started = TimerEngine.startFocus(AppSnapshot(projects = listOf(project)), project.id, 10, timestamp)
        val timer = started.activeTimer!!
        val disk = Disk(LocalDocument(snapshot = started, alarmTickets = listOf(AlarmTicket(timer.id, timer.deadline, timer.completionSound))))
        var delivered = 0
        val store = AppStore(disk, now = { timer.deadline + 100 }, effects = object : StoreEffects {
            override suspend fun synchronize(document: LocalDocument) {}
            override suspend fun deliverCompletion(ticket: AlarmTicket, snapshot: AppSnapshot) { delivered++ }
        })
        store.initialize(); store.execute(AppCommand.Recover); store.execute(AppCommand.AlarmFired(timer.id, timer.deadline))
        assertEquals(0, delivered); assertEquals(1, store.snapshot.sessions.size)
        assertEquals(AlarmDisposition.cancelled, disk.document!!.alarmTickets.single().disposition)
    }
    @Test fun undoGroupsSessionsAndThoughtsAndSurvivesFailedRestore() = runTest {
        val session = FocusSession(newID(), project.id, timestamp, timestamp + 60, 600, SessionOutcome.interrupted)
        val thought = CapturedThought(projectID = project.id, createdAt = timestamp, text = "Remember")
        val disk = Disk(LocalDocument(snapshot = AppSnapshot(projects = listOf(project), sessions = listOf(session), thoughts = listOf(thought))))
        var uptime = 0.0
        val store = AppStore(disk, now = { timestamp }, uptime = { uptime })
        store.initialize()
        store.execute(AppCommand.DeleteSessions(setOf(session.id))); store.execute(AppCommand.DeleteThoughts(setOf(thought.id)))
        assertEquals(2, store.pendingDeletion.value!!.count); assertFalse(store.canDeleteProject(project.id))
        disk.fail = true; assertIs<MutationResult.Failure>(store.execute(AppCommand.UndoDeletion)); assertEquals(2, store.pendingDeletion.value!!.count)
        disk.fail = false; store.execute(AppCommand.UndoDeletion)
        assertEquals(listOf(session), store.snapshot.sessions); assertEquals(listOf(thought), store.snapshot.thoughts)
        store.execute(AppCommand.DeleteThoughts(setOf(thought.id))); uptime = 11.0
        assertIs<MutationResult.Failure>(store.execute(AppCommand.UndoDeletion)); assertNull(store.pendingDeletion.value)
    }
    @Test fun integrationFailureKeepsSuccessfulSave() = runTest {
        val disk = Disk(LocalDocument(snapshot = AppSnapshot(projects = listOf(project))))
        val store = AppStore(disk, now = { timestamp }, effects = StoreEffects { error("notifications unavailable") })
        store.initialize(); assertEquals(MutationResult.Success, store.execute(AppCommand.StartFocus(project.id, 10)))
        assertNotNull(store.snapshot.activeTimer); assertEquals(store.snapshot, disk.document!!.snapshot)
        assertContains(store.errorMessage.value!!, "Saved changes")
    }
    @Test fun projectDraftMergesUneditedConcurrentFieldsButRejectsConflicts() = runTest {
        val disk = Disk(LocalDocument(snapshot = AppSnapshot(projects = listOf(project))))
        val store = AppStore(disk, now = { timestamp }, zone = { ZoneId.of("UTC") })
        store.initialize()
        val baseline = ProjectDraft.from(store.snapshot, project.id, timestamp, ZoneId.of("UTC"))
        store.execute(AppCommand.SaveProjectSettings(baseline.copy(shortBreakMinutes = 7)))
        assertEquals(MutationResult.Success, store.execute(AppCommand.SaveProjectSettings(baseline.copy(name = "Updated"))))
        assertEquals(7, store.snapshot.projects.single().shortBreakMinutes)
        assertIs<MutationResult.Failure>(store.execute(AppCommand.SaveProjectSettings(baseline.copy(name = "Conflict"))))
    }
    @Test fun claimSurvivesNotificationFailure() = runTest {
        var now = timestamp
        val disk = Disk(LocalDocument(snapshot = AppSnapshot(projects = listOf(project))))
        var attempts = 0
        val store = AppStore(disk, now = { now }, effects = object : StoreEffects {
            override suspend fun synchronize(document: LocalDocument) {}
            override suspend fun deliverCompletion(ticket: AlarmTicket, snapshot: AppSnapshot) { attempts++; error("denied") }
        })
        store.initialize(); store.execute(AppCommand.StartFocus(project.id, 10)); val timer = store.snapshot.activeTimer!!; now = timer.deadline
        assertEquals(MutationResult.Success, store.execute(AppCommand.AlarmFired(timer.id, timer.deadline)))
        store.execute(AppCommand.AlarmFired(timer.id, timer.deadline)); assertEquals(1, attempts)
        assertEquals(AlarmDisposition.claimed, disk.document!!.alarmTickets.single().disposition)
    }
    @Test fun initialPersistenceFailureShowsRecoveryWithoutPublishing() = runTest {
        val disk = Disk(); disk.fail = true
        var effects = 0
        val store = AppStore(disk, effects = StoreEffects { effects++ })
        store.initialize()
        assertIs<LoadState.Failed>(store.state.value); assertEquals(0, effects); assertNull(disk.document)
    }
    @Test fun oldAlarmNeverFinishesNewTimer() = runTest {
        var now = timestamp
        val disk = Disk(LocalDocument(snapshot = AppSnapshot(projects = listOf(project))))
        val store = AppStore(disk, now = { now })
        store.initialize(); store.execute(AppCommand.StartFocus(project.id, 10))
        val old = store.snapshot.activeTimer!!; now = old.deadline
        store.execute(AppCommand.Reconcile); store.execute(AppCommand.StartFocus(project.id, 10))
        val current = store.snapshot.activeTimer!!; now = current.deadline
        store.execute(AppCommand.AlarmFired(old.id, old.deadline))
        assertEquals(current, store.snapshot.activeTimer); assertEquals(1, store.snapshot.sessions.size)
    }
    @Test fun cycleEditsRequireIdleAndResetCounter() = runTest {
        val disk = Disk(LocalDocument(snapshot = AppSnapshot(projects = listOf(project), completedInCycle = 2)))
        val store = AppStore(disk, now = { timestamp })
        store.initialize(); store.execute(AppCommand.StartFocus(project.id, 10))
        assertIs<MutationResult.Failure>(store.execute(AppCommand.UpdateSettings(store.snapshot.settings.copy(longBreakInterval = 3))))
        store.execute(AppCommand.EndTimer)
        assertEquals(MutationResult.Success, store.execute(AppCommand.UpdateSettings(store.snapshot.settings.copy(longBreakInterval = 3))))
        assertEquals(0, store.snapshot.completedInCycle)
    }
    @Test fun soundEditUpdatesActiveTimerAndDeliveryTicketAtomically() = runTest {
        val disk = Disk(LocalDocument(snapshot = AppSnapshot(projects = listOf(project))))
        val store = AppStore(disk, now = { timestamp })
        store.initialize(); store.execute(AppCommand.StartFocus(project.id, 10))
        store.execute(AppCommand.UpdateSettings(store.snapshot.settings.copy(focusCompletionSound = CompletionSound.bell)))
        assertEquals(CompletionSound.bell, store.snapshot.activeTimer!!.completionSound)
        assertEquals(CompletionSound.bell, disk.document!!.alarmTickets.single().sound)
    }

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    @Test fun callerCancellationCannotSplitSaveAndPublish() = runTest {
        val enteredSave = CompletableDeferred<Unit>()
        val releaseSave = CompletableDeferred<Unit>()
        var saved = LocalDocument(snapshot = AppSnapshot(projects = listOf(project)))
        var delaySave = false
        val persistence = object : SnapshotPersistence {
            override suspend fun load() = saved
            override suspend fun save(document: LocalDocument) {
                saved = document
                if (delaySave) { enteredSave.complete(Unit); releaseSave.await() }
            }
        }
        val store = AppStore(persistence, now = { timestamp })
        store.initialize(); delaySave = true
        val operation = launch { store.execute(AppCommand.StartFocus(project.id, 10)) }
        enteredSave.await(); operation.cancel(); releaseSave.complete(Unit); operation.join(); runCurrent()
        assertEquals(saved.snapshot, store.snapshot); assertNotNull(store.snapshot.activeTimer)
        delaySave = false
        store.execute(AppCommand.EditIntention(store.snapshot.activeTimer!!.id, true, "Continue"))
        assertEquals(saved.snapshot, store.snapshot)
        assertEquals("Continue", store.snapshot.activeTimer!!.intention)
    }

}
