package com.jamesblack.pomodoro.core

import com.ibm.icu.text.BreakIterator
import java.time.ZoneId
import java.time.DayOfWeek
import java.time.temporal.TemporalAdjusters
import java.util.Locale

object SessionText {
    fun count(text: String): Int { val iterator = BreakIterator.getCharacterInstance(Locale.ROOT); iterator.setText(text); var count = 0; iterator.first(); while (iterator.next() != BreakIterator.DONE) count++; return count }
    fun normalize(text: String?, limit: Int = 280): String? { val value = text?.trim { it.isWhitespace() || Character.isSpaceChar(it) }?.takeIf { it.isNotEmpty() } ?: return null; require(count(value) <= limit) { "Use $limit characters or fewer." }; return value }
}
object SessionPlanText {
    fun items(text: String?): List<String> = (text ?: "").replace("\r\n", "\n").replace('\r', '\n').split('\n').map { it.trim { c -> c.isWhitespace() || Character.isSpaceChar(c) } }.filter { it.isNotEmpty() }
    fun serialize(items: List<String>): String? = SessionText.normalize(items.flatMap { items(it) }.joinToString("\n"))
}
object TimerEngine {
    fun startFocus(state: AppSnapshot, projectID: String, minutes: Int, now: Double = Time.now()): AppSnapshot {
        require(state.activeTimer == null) { "End the current timer first." }
        val project = state.projects.find { it.id == projectID }
        require(minutes in 10..60 && project?.status == ProjectStatus.ongoing) { "Choose an ongoing project and a focus duration from 10 to 60 minutes." }
        requireNotNull(project)
        val timer = ActiveTimer(projectID = projectID, kind = TimerKind.focus, startedAt = now, plannedSeconds = minutes * 60, shortBreakMinutes = project.shortBreakMinutes, longBreakMinutes = project.longBreakMinutes, longBreakInterval = state.settings.longBreakInterval, intention = SessionText.normalize(project.breadcrumb?.text), completionSound = state.settings.completionSound(TimerKind.focus))
        return state.copy(breakOffer = null, activeTimer = timer, projects = state.projects.map { if (it.id == projectID) it.copy(breadcrumb = null) else it })
    }
    fun setBreakDuration(state: AppSnapshot, offer: BreakOffer, minutes: Int): AppSnapshot {
        require(state.activeTimer == null && state.breakOffer == offer && offer.kind != TimerKind.focus && minutes in 1..60 && state.projects.any { it.id == offer.projectID }) { "This break is no longer available to change." }
        return state.copy(breakOffer = offer.copy(minutes = minutes), projects = state.projects.map { if (it.id != offer.projectID) it else if (offer.kind == TimerKind.longBreak) it.copy(longBreakMinutes = minutes) else it.copy(shortBreakMinutes = minutes) })
    }
    fun startBreak(state: AppSnapshot, now: Double = Time.now()): AppSnapshot {
        require(state.activeTimer == null && state.breakOffer != null) { "No break is ready to start." }; val offer = requireNotNull(state.breakOffer)
        return state.copy(activeTimer = ActiveTimer(projectID = offer.projectID, kind = offer.kind, startedAt = now, plannedSeconds = offer.minutes * 60, shortBreakMinutes = 0, longBreakMinutes = 0, longBreakInterval = state.settings.longBreakInterval, completionSound = state.settings.completionSound(offer.kind)), breakOffer = null)
    }
    fun finish(state: AppSnapshot, now: Double = Time.now(), force: Boolean = false): AppSnapshot {
        val timer = state.activeTimer ?: return state
        if (!force && now < timer.deadline) return state
        if (timer.kind != TimerKind.focus) return state.copy(activeTimer = null)
        val completed = now >= timer.deadline
        val sessions = if (state.sessions.any { it.id == timer.id }) state.sessions else state.sessions + FocusSession(timer.id, timer.projectID, timer.startedAt, now.coerceIn(timer.startedAt, timer.deadline), timer.plannedSeconds, if (completed) SessionOutcome.completed else SessionOutcome.interrupted, timer.intention)
        val count = state.completedInCycle + if (completed) 1 else 0
        val isLong = count >= timer.longBreakInterval
        return state.copy(activeTimer = null, sessions = sessions, completedInCycle = if (completed && isLong) 0 else count, breakOffer = if (!completed) state.breakOffer else BreakOffer(timer.projectID, if (isLong) TimerKind.longBreak else TimerKind.shortBreak, if (isLong) timer.longBreakMinutes else timer.shortBreakMinutes))
    }
    fun discardFocus(state: AppSnapshot, timerID: String): AppSnapshot = if (state.activeTimer?.id == timerID && state.activeTimer.kind == TimerKind.focus) state.copy(activeTimer = null) else state
    fun deleteSession(state: AppSnapshot, sessionID: String): AppSnapshot = state.copy(sessions = state.sessions.filterNot { it.id == sessionID })
    fun merge(state: AppSnapshot, source: String, destination: String): AppSnapshot {
        require(source != destination && state.projects.any { it.id == source } && state.projects.any { it.id == destination }) { "Select a different existing destination project." }
        require(state.activeTimer?.projectID !in listOf(source, destination)) { "End the affected project's timer before merging." }
        val from = state.projects.first { it.id == source }; val to = state.projects.first { it.id == destination }
        require(from.breadcrumb == null || to.breadcrumb == null || from.breadcrumb.text == to.breadcrumb.text) { "Resolve the projects' different session plans before merging them." }
        return state.copy(projects = state.projects.filterNot { it.id == source }.map { if (it.id == destination) it.copy(breadcrumb = to.breadcrumb ?: from.breadcrumb) else it }, sessions = state.sessions.map { if (it.projectID == source) it.copy(projectID = destination) else it }, thoughts = state.thoughts.map { if (it.projectID == source) it.copy(projectID = destination) else it }, breakOffer = state.breakOffer?.let { if (it.projectID == source) it.copy(projectID = destination) else it }, goalPlan = state.goalPlan.copy(weeklyProjectRevisions = state.goalPlan.weeklyProjectRevisions.filterNot { it.projectID == source }, dailyProjectRevisions = state.goalPlan.dailyProjectRevisions.filterNot { it.projectID == source }))
    }
}
object ThoughtEngine {
    fun capture(state: AppSnapshot, context: ThoughtCaptureContext, text: String, now: Double = Time.now()): AppSnapshot {
        require(context.projectID == null || state.projects.any { it.id == context.projectID }) { "This project is no longer available." }
        val normalized = requireNotNull(SessionText.normalize(text, 500)) { "Enter a thought before saving." }
        return state.copy(thoughts = state.thoughts + CapturedThought(projectID = context.projectID, originSessionID = context.originSessionID, createdAt = now, text = normalized))
    }
    fun edit(state: AppSnapshot, id: String, text: String): AppSnapshot {
        require(state.thoughts.any { it.id == id }) { "This thought is no longer available." }; val normalized = requireNotNull(SessionText.normalize(text, 500)) { "Enter a thought before saving." }
        return state.copy(thoughts = state.thoughts.map { if (it.id == id) it.copy(text = normalized) else it })
    }
    fun setCompleted(state: AppSnapshot, id: String, completed: Boolean, now: Double = Time.now()): AppSnapshot {
        require(state.thoughts.any { it.id == id }) { "This thought is no longer available." }
        return state.copy(thoughts = state.thoughts.map { if (it.id != id) it else it.copy(completedAt = if (completed) it.completedAt ?: maxOf(now, it.createdAt) else null) })
    }
}
object GoalEngine {
    fun week(containing: Double, zone: ZoneId = ZoneId.systemDefault()): DateInterval { val start = Time.date(containing, zone).with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)); return DateInterval(Time.start(start, zone), Time.start(start.plusWeeks(1), zone)) }
    fun dailyTarget(on: Double, plan: GoalPlan, zone: ZoneId = ZoneId.systemDefault()): Int? = plan.dailyRevisions.filter { it.effectiveFrom <= LocalDay.at(on, zone) }.maxByOrNull { it.effectiveFrom }?.minutes?.get(Time.date(on, zone).dayOfWeek.value - 1)
    fun dailyTarget(projectID: String, on: Double, plan: GoalPlan, zone: ZoneId = ZoneId.systemDefault()): Int? = dailySchedule(projectID, on, plan, zone)?.get(Time.date(on, zone).dayOfWeek.value - 1)
    fun dailySchedule(projectID: String, on: Double, plan: GoalPlan, zone: ZoneId = ZoneId.systemDefault()): List<Int>? = plan.dailyProjectRevisions.filter { it.projectID == projectID && it.effectiveFrom <= LocalDay.at(on, zone) }.maxByOrNull { it.effectiveFrom }?.minutes
    fun weeklyTarget(projectID: String, weekStart: Double, plan: GoalPlan, zone: ZoneId = ZoneId.systemDefault()): Int? = plan.weeklyProjectRevisions.filter { it.projectID == projectID && it.effectiveFrom <= LocalDay.at(week(weekStart, zone).start, zone) }.maxByOrNull { it.effectiveFrom }?.minutes
    fun setDaily(plan: GoalPlan, projectID: String, minutes: List<Int>, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): GoalPlan {
        require(minutes.size == 7 && minutes.all { it in 0..1440 }) { "Choose seven daily targets from 0 to 1440 minutes." }; val day = LocalDay.at(now, zone)
        return plan.copy(dailyProjectRevisions = plan.dailyProjectRevisions.filterNot { it.projectID == projectID && it.effectiveFrom == day } + ProjectDailyGoalRevision(projectID, day, minutes))
    }
    fun weeklyEffectiveDate(projectID: String, plan: GoalPlan, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): Double = week(now, zone).start
    fun setWeekly(plan: GoalPlan, projectID: String, minutes: Int?, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault(), effectiveWeek: Double? = null): GoalPlan {
        require(minutes == null || minutes in 1..10080) { "Weekly targets must be 1 to 10080 minutes." }; val monday = week(effectiveWeek ?: now, zone).start
        require(monday >= week(now, zone).start) { "Choose this week or a future week." }; val day = LocalDay.at(monday, zone)
        return plan.copy(weeklyProjectRevisions = plan.weeklyProjectRevisions.filterNot { it.projectID == projectID && it.effectiveFrom == day } + ProjectWeeklyGoalRevision(projectID, day, minutes))
    }
    fun validate(plan: GoalPlan, projectIDs: Set<String>) {
        fun schedule(minutes: List<Int>) { require(minutes.size == 7 && minutes.all { it in 0..1440 }) { "Invalid daily goal schedule." } }
        require(plan.dailyRevisions.map { it.effectiveFrom }.distinct().size == plan.dailyRevisions.size) { "Duplicate daily goal revisions." }
        plan.dailyRevisions.forEach { it.effectiveFrom.date(); schedule(it.minutes) }; plan.legacyDailyGoalTransitionDay?.date()
        plan.pendingLegacyDailySchedule?.let { require(plan.legacyDailyGoalTransitionDay != null); schedule(it) }
        require(plan.dailyProjectRevisions.map { it.projectID to it.effectiveFrom }.distinct().size == plan.dailyProjectRevisions.size)
        plan.dailyProjectRevisions.forEach { require(it.projectID in projectIDs); it.effectiveFrom.date(); schedule(it.minutes) }
        require(plan.weeklyProjectRevisions.map { it.projectID to it.effectiveFrom }.distinct().size == plan.weeklyProjectRevisions.size)
        plan.weeklyProjectRevisions.forEach { require(it.projectID in projectIDs && it.effectiveFrom.date().dayOfWeek == DayOfWeek.MONDAY && (it.minutes == null || it.minutes in 1..10080)) { "Invalid project weekly goal." } }
    }
}
