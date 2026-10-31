package com.jamesblack.pomodoro.core

import java.io.File
import java.time.ZoneId
import kotlin.test.*

/** The input was produced by BackupService.exportSavedData from the Swift core. */
class BackupPortabilityTest {
    @Test fun richSwiftSchema9FixtureRoundTripsThroughAndroid() {
        val input = javaClass.getResourceAsStream("/swift-v9-rich.json")!!.use { it.readBytes() }
        val state = BackupCodec.decode(input, now = 815000000.125, zone = ZoneId.of("Europe/Stockholm"))
        assertEquals(9, state.schemaVersion)
        assertEquals(2, state.projects.size); assertEquals(2, state.sessions.size); assertEquals(2, state.thoughts.size)
        assertEquals("Writing 👨‍👩‍👧‍👦", state.projects.first().name)
        assertEquals("First task\nSecond task 🇸🇪", state.projects.first().breadcrumb?.text)
        assertEquals(40, state.projects.first().preferredFocusMinutes)
        assertEquals(49.75, state.sessions.last().duration)
        assertEquals(814999349.75, state.sessions.first().startedAt)
        assertEquals("Review e\u0301", state.sessions.first().intention)
        assertEquals(CompletionSound.ripple, state.settings.focusCompletionSound)
        assertEquals(CompletionSound.wood, state.settings.breakCompletionSound)
        assertEquals(5, state.settings.consistencyTargetDays)
        assertNull(state.thoughts.last().projectID); assertNull(state.thoughts.last().completedAt)
        assertNotNull(state.thoughts.first().completedAt)
        assertEquals(listOf(20, 30, 40, 50, 60, 0, 0), state.goalPlan.dailyProjectRevisions.single().minutes)
        assertNull(state.goalPlan.weeklyProjectRevisions.last().minutes)
        assertEquals(600, state.goalPlan.weeklyProjectRevisions.first().minutes)
        assertEquals(LocalDay(2026, 10, 26), state.goalPlan.legacyDailyGoalTransitionDay)
        assertEquals(TimerKind.longBreak, state.breakOffer?.kind)
        val exported = BackupCodec.encodeSaved(state)
        assertEquals(state, BackupCodec.decode(exported))
        // A standalone verifier compiles current Swift core and compares this export to its source fixture.
        val directory = File("build/backup-portability").apply { mkdirs() }
        File(directory, "android-v9.json").writeBytes(exported)
    }
    @Test fun malformedUtf8AndMissingSchemaAreReportedAsInvalidData() {
        val valid = BackupCodec.encode(AppSnapshot()).toString(Charsets.UTF_8)
        val bytes = valid.replace("\"projects\"", "\"invalid\"").toByteArray()
        assertFailsWith<IllegalArgumentException> { BackupCodec.decode(bytes) }
        assertFailsWith<IllegalArgumentException> { BackupCodec.decode("{}".toByteArray()) }
        val bad = "{\"schemaVersion\":9,\"unknown\":\"".toByteArray() + byteArrayOf(0xC3.toByte(), 0x28) + "\"}".toByteArray()
        assertFailsWith<IllegalArgumentException> { BackupCodec.decode(bad) }
        assertFailsWith<IllegalArgumentException> { LocalDay(2026, 2, 30).date() }
    }

}
