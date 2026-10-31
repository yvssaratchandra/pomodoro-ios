package com.jamesblack.pomodoro.platform

import android.app.Application
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, manifest = Config.NONE)
class AtomicSnapshotPersistenceTest {
    @get:Rule val folder = TemporaryFolder()
    private val json = Json { encodeDefaults = true }
    private fun file() = File(folder.root, "document.json")
    @Test fun freshStorageIsAbsentAndRoundtripPreservesFractionalDatesAndTickets() = runTest {
        val file = file(); val persistence = AtomicSnapshotPersistence(file)
        assertNull(persistence.load())
        val project = Project(name = "Work", createdAt = 800000000.123456)
        val snapshot = TimerEngine.startFocus(AppSnapshot(projects = listOf(project)), project.id, 10, 800000000.654321)
        val timer = snapshot.activeTimer!!
        val document = LocalDocument(snapshot = snapshot, alarmTickets = listOf(AlarmTicket(timer.id, timer.deadline, timer.completionSound)))
        persistence.save(document)
        assertEquals(document, AtomicSnapshotPersistence(file).load())
    }
    @Test fun malformedCurrentSnapshotFailsWithoutReplacingBytes() = runTest {
        val file = file(); val valid = json.encodeToJsonElement(LocalDocument.serializer(), LocalDocument()).jsonObject
        val snapshot = valid.getValue("snapshot").jsonObject - "thoughts"
        val bytes = JsonObject(valid + ("snapshot" to JsonObject(snapshot))).toString().encodeToByteArray()
        file.writeBytes(bytes)
        try { AtomicSnapshotPersistence(file).load(); fail("Missing required field must fail") } catch (_: IllegalArgumentException) {}
        assertArrayEquals(bytes, file.readBytes())
    }
    @Test fun unsupportedEnvelopeAndInvalidAlarmRecordsPreserveOriginalBytes() = runTest {
        val project = Project(name = "Work")
        val ticket = AlarmTicket(newID(), 800000000.5, CompletionSound.bell)
        val valid = json.encodeToJsonElement(LocalDocument.serializer(), LocalDocument(snapshot = AppSnapshot(projects = listOf(project)), alarmTickets = listOf(ticket, ticket))).jsonObject
        val variants = listOf(JsonObject(valid + ("version" to JsonPrimitive(999))), JsonObject(valid))
        for (variant in variants) {
            val bytes = variant.toString().encodeToByteArray(); val file = file(); file.writeBytes(bytes)
            try { AtomicSnapshotPersistence(file).load(); fail("Invalid envelope must fail") } catch (_: IllegalArgumentException) {}
            assertArrayEquals(bytes, file.readBytes())
        }
    }
    @Test fun oldSchemaIsMigratedInMemoryThenPersistedByStore() = runTest {
        val file = file()
        val current = json.encodeToJsonElement(LocalDocument.serializer(), LocalDocument()).jsonObject
        val snapshot = current.getValue("snapshot").jsonObject.toMutableMap()
        snapshot["schemaVersion"] = JsonPrimitive(8)
        val plan = snapshot.getValue("goalPlan").jsonObject - setOf("dailyProjectRevisions", "pendingLegacyDailySchedule", "legacyDailyGoalTransitionDay")
        snapshot["goalPlan"] = JsonObject(plan)
        val bytes = JsonObject(current + ("snapshot" to JsonObject(snapshot))).toString().encodeToByteArray(); file.writeBytes(bytes)
        val persistence = AtomicSnapshotPersistence(file)
        assertEquals(9, persistence.load()!!.snapshot.schemaVersion)
        assertArrayEquals(bytes, file.readBytes())
        val store = AppStore(persistence); store.initialize()
        assertTrue(store.state.value is LoadState.Ready)
        val persisted = json.parseToJsonElement(file.readText()).jsonObject.getValue("snapshot").jsonObject
        assertEquals(9, persisted.getValue("schemaVersion").jsonPrimitive.int)
    }
    @Test fun interruptedAtomicWriteRecoversBackupInsteadOfPartialBase() = runTest {
        val file = file(); val persistence = AtomicSnapshotPersistence(file)
        val document = LocalDocument(snapshot = AppSnapshot(projects = listOf(Project(name = "Retained"))))
        persistence.save(document)
        File(file.path + ".bak").writeBytes(file.readBytes()); file.writeText("partial")
        assertEquals(document, persistence.load())
    }
}
