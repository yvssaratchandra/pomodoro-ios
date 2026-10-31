package com.jamesblack.pomodoro.core

import kotlin.test.*
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.*

class CoreParityTest {
    private val zone = ZoneId.of("Europe/Stockholm")
    private fun at(value: String) = Time.fromInstant(Instant.parse(value))
    private fun fixture(name: String) = javaClass.getResourceAsStream("/$name")!!.use { it.readBytes() }
    private val project = Project(name = "Writing", createdAt = 0.0)
    private val initial get() = AppSnapshot(projects = listOf(project))
    private fun change(bytes: ByteArray, edit: (MutableMap<String, JsonElement>) -> Unit): ByteArray { val doc = Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject.toMutableMap(); edit(doc); return JsonObject(doc).toString().toByteArray() }

    @Test fun historicalSwiftFixtureMigratesWithoutLosingSubseconds() {
        val now = at("2026-10-31T12:00:00Z")
        val state = BackupCodec.decode(fixture("v1-history.json"), now, zone)
        assertEquals(9, state.schemaVersion); assertEquals(40, state.projects.single().preferredFocusMinutes)
        assertEquals(59.75, state.sessions.last().duration); assertEquals(770000000.125, state.projects.single().createdAt)
        assertEquals(CompletionSound.systemDefault, state.settings.focusCompletionSound)
        assertEquals(List(7) { 240 }, state.goalPlan.pendingLegacyDailySchedule)
        assertEquals(LocalDay(2026, 10, 31), state.goalPlan.legacyDailyGoalTransitionDay)
        assertEquals(state, BackupCodec.decode(BackupCodec.encodeSaved(state), now, zone))
    }
    @Test fun runningFixtureRequiresStorageDecodeAndRetainsCapturedMute() {
        val bytes = fixture("v1-running.json")
        assertFails { BackupCodec.decode(bytes) }
        val state = BackupCodec.decode(bytes, forBackup = false)
        assertNotNull(state.activeTimer); assertEquals(CompletionSound.silent, state.activeTimer.completionSound)
        assertNull(BackupCodec.decode(BackupCodec.encodeSaved(state)).activeTimer)
    }
    @Test fun missingRequiredCurrentAndLegacyFieldsAreRejected() {
        val bytes = BackupCodec.encode(initial)
        listOf("sessions", "thoughts", "projects", "completedInCycle", "settings", "goalPlan").forEach { key -> assertFails(key) { BackupCodec.decode(change(bytes) { it.remove(key) }) } }
        assertFails { BackupCodec.decode(change(fixture("v1-history.json")) { doc -> doc["settings"] = JsonObject(doc.getValue("settings").jsonObject - "haptics") }) }
        assertFails { BackupCodec.decode(change(bytes) { it["schemaVersion"] = JsonPrimitive(10) }) }
        assertFails { BackupCodec.decode(change(bytes) { it["projects"] = JsonArray(listOf(JsonObject(Json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject.getValue("projects").jsonArray.single().jsonObject - "status"))) }) }
    }
    @Test fun uuidCaseCanonicalizationMatchesSwiftIdentity() {
        val bytes = BackupCodec.encode(initial)
        val lower = bytes.toString(Charsets.UTF_8).replace(project.id, project.id.lowercase()).toByteArray()
        assertEquals(project.id, BackupCodec.decode(lower).projects.single().id)
        assertFails { BackupCodec.decode(bytes.toString(Charsets.UTF_8).replace(project.id, "1-1-1-1-1").toByteArray()) }
    }
    @Test fun capturedPlanAndSoundBelongToStartedTimer() {
        val state = initial.copy(projects = listOf(project.copy(breadcrumb = ProjectBreadcrumb("First\nSecond", 0.0))), settings = Settings(focusCompletionSound = CompletionSound.bell))
        val started = TimerEngine.startFocus(state, project.id, 10, 100.125)
        assertNull(started.projects.single().breadcrumb); assertEquals("First\nSecond", started.activeTimer?.intention)
        val changed = started.copy(settings = started.settings.copy(focusCompletionSound = CompletionSound.chime))
        val finished = TimerEngine.finish(changed, 9999.0)
        assertEquals(CompletionSound.bell, started.activeTimer?.completionSound)
        assertEquals(700.125, finished.sessions.single().endedAt); assertEquals(600.0, finished.sessions.single().duration)
        assertEquals(TimerKind.shortBreak, finished.breakOffer?.kind)
        assertEquals(finished, TimerEngine.finish(finished, 9999.0))
    }
    @Test fun interruptedDiscardedAndBreakRules() {
        val started = TimerEngine.startFocus(initial, project.id, 10, 100.0)
        assertEquals(started, TimerEngine.finish(started, 200.0))
        val ended = TimerEngine.finish(started, 200.0, force = true)
        assertEquals(SessionOutcome.interrupted, ended.sessions.single().outcome); assertNull(ended.breakOffer); assertEquals(0, ended.completedInCycle)
        val discarded = TimerEngine.discardFocus(started, started.activeTimer!!.id)
        assertNull(discarded.activeTimer); assertTrue(discarded.sessions.isEmpty())
        val completed = TimerEngine.finish(started.copy(completedInCycle = 3), 700.0)
        assertEquals(TimerKind.longBreak, completed.breakOffer?.kind); assertEquals(0, completed.completedInCycle)
        val breakState = TimerEngine.startBreak(completed, 701.0)
        assertNull(breakState.breakOffer); assertEquals(completed.sessions, TimerEngine.finish(breakState, 702.0, true).sessions)
    }
    @Test fun independentThoughtContextSurvivesDiscardAndCompletionIsIdempotent() {
        val started = TimerEngine.startFocus(initial, project.id, 10, 0.0)
        val timerID = started.activeTimer!!.id
        val captured = ThoughtEngine.capture(started, ThoughtCaptureContext(project.id, timerID), " hello ", 10.0)
        val thought = captured.thoughts.single(); assertEquals("hello", thought.text)
        val discarded = TimerEngine.discardFocus(captured, timerID); assertEquals(listOf(thought), discarded.thoughts)
        val checked = ThoughtEngine.setCompleted(discarded, thought.id, true, 20.0)
        assertEquals(checked, ThoughtEngine.setCompleted(checked, thought.id, true, 30.0))
        assertNull(ThoughtEngine.setCompleted(checked, thought.id, false, 40.0).thoughts.single().completedAt)
    }
    @Test fun mergePreservesDestinationGoalsAndRejectsConflictingPlans() {
        val second = Project(name = "Other", createdAt = 0.0)
        val state = initial.copy(projects = listOf(project.copy(breadcrumb = ProjectBreadcrumb("a", 0.0)), second.copy(breadcrumb = ProjectBreadcrumb("b", 0.0))))
        assertFails { TimerEngine.merge(state, project.id, second.id) }
        val transferable = state.copy(projects = listOf(state.projects.first(), second), goalPlan = GoalEngine.setDaily(GoalPlan(), project.id, List(7) { 20 }, 0.0, zone))
        val merged = TimerEngine.merge(transferable, project.id, second.id)
        assertEquals("a", merged.projects.single().breadcrumb?.text); assertTrue(merged.goalPlan.dailyProjectRevisions.isEmpty())
    }
    @Test fun unicodeLimitsUseExtendedGraphemes() {
        val family = "👨‍👩‍👧‍👦"; val flag = "🇸🇪"; val accented = "e\u0301"
        assertEquals(3, SessionText.count(family + flag + accented))
        assertEquals(family.repeat(280), SessionText.normalize(family.repeat(280)))
        assertFails { SessionText.normalize(family.repeat(281)) }
        assertNull(SessionText.normalize("\u00a0 \n"))
    }
    @Test fun goalsAreProjectOwnedAndDatedWithoutHistoricalFabrication() {
        val now = at("2026-10-28T12:00:00Z")
        val plan = GoalEngine.setDaily(GoalPlan(), project.id, listOf(0, 10, 20, 30, 40, 50, 60), now, zone)
        assertNull(GoalEngine.dailyTarget(project.id, now - 86400, plan, zone)); assertEquals(20, GoalEngine.dailyTarget(project.id, now, plan, zone))
        assertNull(GoalEngine.dailyTarget("another", now, plan, zone)); assertNull(GoalEngine.dailyTarget(now, plan, zone))
        val weekly = GoalEngine.setWeekly(plan, project.id, 600, now, zone)
        assertEquals(600, GoalEngine.weeklyTarget(project.id, now, weekly, zone))
        assertFails { GoalEngine.setWeekly(plan, project.id, 600, now, zone, now - 7 * 86400) }
        assertFails { GoalEngine.setDaily(plan, project.id, listOf(20), now, zone) }
        assertFails { GoalEngine.validate(plan.copy(dailyProjectRevisions = plan.dailyProjectRevisions + plan.dailyProjectRevisions), setOf(project.id)) }
    }
    @Test fun savedOnlyTotalsSplitAtMidnightAcrossDST() {
        val start = at("2026-03-28T22:50:00Z") // 23:50 local before spring change
        val session = FocusSession(newID(), project.id, start, start + 1200, 1200, SessionOutcome.completed)
        val state = initial.copy(sessions = listOf(session), activeTimer = ActiveTimer(projectID = project.id, kind = TimerKind.focus, startedAt = start + 1300, plannedSeconds = 600, shortBreakMinutes = 5, longBreakMinutes = 15, longBreakInterval = 4))
        val days = Statistics.dailySummaries(state, Statistics.interval(FocusPeriod.week, start + 1200, zone), now = start + 1800, zone = zone)
        assertEquals(600.0, days.first { Time.date(it.date, zone).dayOfMonth == 28 }.focusSeconds)
        assertEquals(600.0, days.first { Time.date(it.date, zone).dayOfMonth == 29 }.focusSeconds)
        assertEquals(1200.0, Statistics.total(state, now = start + 1800))
        assertEquals(23 * 3600.0, Statistics.today(at("2026-03-29T12:00:00Z"), zone).duration)
        assertEquals(25 * 3600.0, Statistics.today(at("2026-10-25T12:00:00Z"), zone).duration)
        assertEquals(1, days.sumOf { it.completedCount })
    }
    @Test fun partialComparisonsUseElapsedCalendarDaysAndClampShortMonths() {
        val now = at("2026-03-31T08:00:00Z"); val range = Statistics.interval(FocusPeriod.month, now, zone)
        val comparison = Statistics.periodComparison(initial, FocusPeriod.month, range, now = now, zone = zone)
        assertEquals(Statistics.interval(FocusPeriod.month, at("2026-02-01T08:00:00Z"), zone).end, comparison.previous.end)
        assertNull(comparison.percentage)
        assertEquals(31, Statistics.periodSummary(initial, range, now = now, zone = zone).elapsedDays)
    }
    @Test fun dateSelectionClampsFutureAndResetsWithRange() {
        val now = at("2026-10-31T12:00:00Z")
        val selection = StatsDateSelection().select(now + 86400, now, zone)
        assertTrue(selection.isCurrent(now, zone)); assertFalse(selection.canMoveForward(now, zone))
        val moved = selection.move(-1, now, zone); assertTrue(moved.canMoveForward(now, zone)); assertTrue(moved.move(1, now, zone).isCurrent(now, zone))
        assertNull(moved.setRange(StatsDateRange.month).anchor)
        assertEquals(53, StatsPeriodOptions.weeks(2020, now, zone).size)
    }
    @Test fun planCandidateDoesNotAdoptBeforePersistenceAndPreservesRowIdentity() {
        val draft = SessionPlanDraft("One\nTwo\nOne")
        val candidate = draft.candidate(SessionPlanDraft.Mutation.Edit(draft.rows[1].id, "Two edited\nThree"))
        assertEquals("Two", draft.rows[1].text); assertEquals(draft.rows[1].id, candidate.rows[1].id)
        assertEquals("One\nTwo edited\nThree\nOne", candidate.text)
        val reconciled = draft.reconcile("One\nOne")
        assertEquals(listOf(draft.rows[0].id, draft.rows[2].id), reconciled.rows.map { it.id })
        assertFails { draft.candidate(SessionPlanDraft.Mutation.Add(" ")) }
    }
    @Test fun validationRejectsDuplicateIDsAndNonfiniteTimestampsAndInvalidCompletion() {
        assertFails { BackupCodec.validate(initial.copy(projects = listOf(project, project))) }
        assertFails { BackupCodec.validate(initial.copy(projects = listOf(project.copy(createdAt = Double.NaN)))) }
        assertFails { BackupCodec.validate(initial.copy(sessions = listOf(FocusSession(newID(), project.id, 0.0, 599.0, 600, SessionOutcome.completed)))) }
        assertEquals("<1 min", DurationText.summary(59.75)); assertEquals("59 sec", DurationText.work(59.75)); assertEquals("01:00", DurationText.countdown(59.75))
    }
    @Test fun routeRoundTripsAreStrictAndCanonical() {
        val routes = listOf(AppRoute.Timer, AppRoute.NewProject, AppRoute.StartFocus(project.id), AppRoute.CaptureThought(), AppRoute.CaptureThought(project.id), AppRoute.PlanNextSession(project.id))
        routes.forEach { assertEquals(it, AppRouter.parse(AppRouter.url(it))) }
        assertEquals(AppRoute.StartFocus(project.id), AppRouter.parse("pomodoro://focus?project=${project.id.lowercase()}&action=start"))
        listOf("pomodoro://timer/", "pomodoro://timer?", "pomodoro://user@timer", "pomodoro://timer#x", "pomodoro://timer:80", "https://timer", "pomodoro://thoughts/new?session=1-1-1-1-1", "pomodoro://focus?project=${project.id}&action=start&action=start", "pomodoro://plan/next?project=${project.id}&extra=1").forEach { assertNull(AppRouter.parse(it), it) }
    }

}
