package com.jamesblack.pomodoro.core

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlin.math.*

object Time {
    const val referenceEpochSeconds = 978307200L
    fun now(): Double = fromInstant(Instant.now())
    fun toInstant(value: Double): Instant { val whole = floor(value).toLong(); return Instant.ofEpochSecond(whole + referenceEpochSeconds, ((value - whole) * 1e9).roundToLong()) }
    fun fromInstant(value: Instant): Double = (value.epochSecond - referenceEpochSeconds).toDouble() + value.nano / 1e9
    fun date(value: Double, zone: ZoneId = ZoneId.systemDefault()): LocalDate = toInstant(value).atZone(zone).toLocalDate()
    fun start(date: LocalDate, zone: ZoneId): Double = fromInstant(date.atStartOfDay(zone).toInstant())
}
fun newID(): String = UUID.randomUUID().toString().uppercase()
@Serializable enum class ProjectStatus(val title: String) { ongoing("Active"), suspended("On hold"), completed("Completed") }
@Serializable enum class SessionOutcome { completed, interrupted }
@Serializable enum class TimerKind(val title: String) { focus("Focus"), shortBreak("Short break"), longBreak("Long break") }
@Serializable enum class Appearance { system, light, dark }
@Serializable enum class CompletionSound(val title: String) {
    systemDefault("System Default"), silent("Silent"), bell("Bell"), chime("Chime"), softTap("Soft Tap"), digital("Digital"), mellow("Mellow"), wood("Wood"), ripple("Ripple");
    val filename: String? get() = if (this == systemDefault || this == silent) null else "$name.wav"
}
@Serializable data class ProjectBreadcrumb(val text: String, val updatedAt: Double, val originSessionID: String? = null)
@Serializable data class Project(val id: String = newID(), val name: String, val status: ProjectStatus = ProjectStatus.ongoing, val focusMinutes: Int = 25, val lastFocusMinutes: Int? = null, val shortBreakMinutes: Int = 5, val longBreakMinutes: Int = 15, val createdAt: Double = Time.now(), val breadcrumb: ProjectBreadcrumb? = null) {
    val preferredFocusMinutes: Int get() = lastFocusMinutes ?: focusMinutes
}
@Serializable data class FocusSession(val id: String, val projectID: String, val startedAt: Double, val endedAt: Double, val plannedSeconds: Int, val outcome: SessionOutcome, val intention: String? = null, val nextStep: String? = null) { val duration: Double get() = max(0.0, endedAt - startedAt) }
@Serializable data class ActiveTimer(val id: String = newID(), val projectID: String, val kind: TimerKind, val startedAt: Double, val plannedSeconds: Int, val shortBreakMinutes: Int, val longBreakMinutes: Int, val longBreakInterval: Int, val intention: String? = null, val completionSound: CompletionSound = CompletionSound.systemDefault) {
    val deadline: Double get() = startedAt + plannedSeconds
    fun elapsed(at: Double): Double = (at - startedAt).coerceIn(0.0, plannedSeconds.toDouble())
}
@Serializable data class BreakOffer(val projectID: String, val kind: TimerKind, val minutes: Int)
@Serializable data class Settings(val dailyGoalMinutes: Int = 240, val defaultFocusMinutes: Int = 25, val defaultShortBreakMinutes: Int = 5, val defaultLongBreakMinutes: Int = 15, val longBreakInterval: Int = 4, val notificationSound: Boolean = true, val focusCompletionSound: CompletionSound = CompletionSound.systemDefault, val breakCompletionSound: CompletionSound = CompletionSound.systemDefault, val haptics: Boolean = true, val appearance: Appearance = Appearance.system, val showProjectNameOnLockScreen: Boolean = false, val showIntentionOnLockScreen: Boolean = false, val consistencyTargetDays: Int = 4) {
    fun completionSound(kind: TimerKind): CompletionSound = if (!notificationSound) CompletionSound.silent else if (kind == TimerKind.focus) focusCompletionSound else breakCompletionSound
}
@Serializable data class CapturedThought(val id: String = newID(), val projectID: String? = null, val originSessionID: String? = null, val createdAt: Double, val text: String, val completedAt: Double? = null)
data class ThoughtCaptureContext(val projectID: String? = null, val originSessionID: String? = null, val id: String = newID())
@Serializable data class LocalDay(val year: Int, val month: Int, val day: Int): Comparable<LocalDay> {
    constructor(date: LocalDate): this(date.year, date.monthValue, date.dayOfMonth)
    fun date(): LocalDate { require(year > 0) { "Invalid calendar date." }; return try { LocalDate.of(year, month, day) } catch (error: java.time.DateTimeException) { throw IllegalArgumentException("Invalid calendar date.", error) } }
    override fun compareTo(other: LocalDay): Int = compareValuesBy(this, other, { it.year }, { it.month }, { it.day })
    companion object { fun at(time: Double, zone: ZoneId = ZoneId.systemDefault()) = LocalDay(Time.date(time, zone)) }
}
@Serializable data class DailyGoalRevision(val effectiveFrom: LocalDay, val minutes: List<Int>)
@Serializable data class ProjectWeeklyGoalRevision(val projectID: String, val effectiveFrom: LocalDay, val minutes: Int? = null)
@Serializable data class ProjectDailyGoalRevision(val projectID: String, val effectiveFrom: LocalDay, val minutes: List<Int>)
@Serializable data class GoalPlan(val dailyRevisions: List<DailyGoalRevision> = emptyList(), val weeklyProjectRevisions: List<ProjectWeeklyGoalRevision> = emptyList(), val dailyProjectRevisions: List<ProjectDailyGoalRevision> = emptyList(), val pendingLegacyDailySchedule: List<Int>? = null, val legacyDailyGoalTransitionDay: LocalDay? = null)
@Serializable data class AppSnapshot(val schemaVersion: Int = currentSchemaVersion, val projects: List<Project> = emptyList(), val sessions: List<FocusSession> = emptyList(), val thoughts: List<CapturedThought> = emptyList(), val settings: Settings = Settings(), val goalPlan: GoalPlan = GoalPlan(), val activeTimer: ActiveTimer? = null, val breakOffer: BreakOffer? = null, val completedInCycle: Int = 0) { companion object { const val currentSchemaVersion = 9 } }
data class DateInterval(val start: Double, val end: Double) { init { require(end >= start) }; val duration: Double get() = end - start }
object DurationText {
    fun summary(seconds: Double): String = when { seconds <= 0 -> "0 min"; seconds < 60 -> "<1 min"; else -> minutes(seconds.toLong() / 60) }
    fun work(seconds: Double): String = if (seconds < 60) "${max(0, seconds.toLong())} sec" else minutes(seconds.toLong() / 60)
    private fun minutes(value: Long): String = if (value < 60) "$value min" else if (value % 60 == 0L) "${value / 60} hr" else "${value / 60} hr ${value % 60} min"
    fun countdown(seconds: Double): String { val value = max(0, ceil(seconds).toLong()); return "%02d:%02d".format(java.util.Locale.ROOT, value / 60, value % 60) }
}
