package com.jamesblack.pomodoro.core

import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.IsoFields

enum class FocusPeriod { week, month }
enum class StatsDateRange(val title: String) { day("Day"), week("Week"), month("Month"), all("All"); val period: FocusPeriod? get() = when (this) { week -> FocusPeriod.week; month -> FocusPeriod.month; else -> null } }
data class DailySummary(val date: Double, val focusSeconds: Double = 0.0, val completedCount: Int = 0, val interruptedCount: Int = 0, val targetMinutes: Int? = null, val isFuture: Boolean)
data class ProjectDuration(val id: String, val name: String, val seconds: Double)
data class PeriodSummary(val interval: DateInterval, val totalSeconds: Double, val elapsedDays: Int, val completedCount: Int, val interruptedCount: Int, val days: List<DailySummary>, val projects: List<ProjectDuration>) { val averageSeconds: Double get() = if (elapsedDays > 0) totalSeconds / elapsedDays else 0.0 }
data class PeriodComparison(val current: DateInterval, val previous: DateInterval, val currentSeconds: Double, val previousSeconds: Double) { val delta: Double get() = currentSeconds - previousSeconds; val percentage: Double? get() = if (previousSeconds > 0) delta / previousSeconds * 100 else null }
data class ConsistencySummary(val week: DateInterval, val focusedDays: Int, val targetDays: Int)
object Statistics {
    fun overlap(start: Double, end: Double, interval: DateInterval): Double = maxOf(0.0, minOf(end, interval.end) - maxOf(start, interval.start))
    fun total(state: AppSnapshot, projectID: String? = null, interval: DateInterval? = null, now: Double = Time.now()): Double = state.sessions.filter { projectID == null || it.projectID == projectID }.sumOf { if (interval == null) it.duration else overlap(it.startedAt, it.endedAt, interval) }
    fun hasFocusInProgress(state: AppSnapshot, projectID: String? = null, interval: DateInterval? = null, now: Double = Time.now()): Boolean {
        val timer = state.activeTimer ?: return false
        if (timer.kind != TimerKind.focus || (projectID != null && timer.projectID != projectID) || timer.startedAt > now || now >= timer.deadline) return false
        if (interval == null) return true
        if (interval.end <= interval.start) return false
        return if (now == timer.startedAt) now >= interval.start && now < interval.end else overlap(timer.startedAt, now, interval) > 0
    }
    fun today(date: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): DateInterval { val day = Time.date(date, zone); return DateInterval(Time.start(day, zone), Time.start(day.plusDays(1), zone)) }
    fun dailyAverage(state: AppSnapshot, projectID: String, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): Double = total(state, projectID, DateInterval(Time.start(Time.date(now, zone).minusDays(6), zone), today(now, zone).end), now) / 7
    fun sessionsToday(state: AppSnapshot, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): List<FocusSession> { val day = today(now, zone); return state.sessions.filter { overlap(it.startedAt, it.endedAt, day) > 0 || (it.duration == 0.0 && it.startedAt >= day.start && it.startedAt < day.end) }.sortedByDescending { it.startedAt } }
    fun interval(period: FocusPeriod, containing: Double, zone: ZoneId = ZoneId.systemDefault()): DateInterval { if (period == FocusPeriod.week) return GoalEngine.week(containing, zone); val day = Time.date(containing, zone).withDayOfMonth(1); return DateInterval(Time.start(day, zone), Time.start(day.plusMonths(1), zone)) }
    private fun reportingEnd(interval: DateInterval, now: Double, zone: ZoneId): Double = maxOf(interval.start, minOf(interval.end, today(now, zone).end))
    fun dailySummaries(state: AppSnapshot, interval: DateInterval, projectID: String? = null, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): List<DailySummary> {
        val end = reportingEnd(interval, now, zone)
        val result = mutableListOf<DailySummary>(); var day = Time.date(interval.start, zone)
        while (Time.start(day, zone) < interval.end) {
            val start = Time.start(day, zone); val next = Time.start(day.plusDays(1), zone)
            val target = if (projectID != null) GoalEngine.dailyTarget(projectID, start, state.goalPlan, zone) else if (state.goalPlan.legacyDailyGoalTransitionDay?.let { LocalDay(day) >= it } == true) null else GoalEngine.dailyTarget(start, state.goalPlan, zone)
            var seconds = 0.0; var completed = 0; var interrupted = 0
            state.sessions.filter { projectID == null || it.projectID == projectID }.forEach { session ->
                if (minOf(next, end) > maxOf(start, interval.start)) seconds += overlap(session.startedAt, session.endedAt, DateInterval(maxOf(start, interval.start), minOf(next, end)))
                if (session.startedAt >= maxOf(start, interval.start) && session.startedAt < minOf(next, end)) { if (session.outcome == SessionOutcome.completed) completed++ else interrupted++ }
            }
            result += DailySummary(start, seconds, completed, interrupted, target, start > now); day = day.plusDays(1)
        }
        return result
    }
    fun periodSummary(state: AppSnapshot, interval: DateInterval, projectID: String? = null, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): PeriodSummary {
        val days = dailySummaries(state, interval, projectID, now, zone); val bounded = DateInterval(interval.start, reportingEnd(interval, now, zone))
        val totals = state.sessions.filter { projectID == null || it.projectID == projectID }.groupBy { it.projectID }.mapValues { (_, sessions) -> sessions.sumOf { overlap(it.startedAt, it.endedAt, bounded) } }
        val projects = state.projects.mapNotNull { p -> totals[p.id]?.takeIf { it > 0 }?.let { ProjectDuration(p.id, p.name, it) } }.sortedWith(compareByDescending<ProjectDuration> { it.seconds }.thenBy { it.name })
        return PeriodSummary(interval, days.sumOf { it.focusSeconds }, days.count { !it.isFuture }, days.sumOf { it.completedCount }, days.sumOf { it.interruptedCount }, days, projects)
    }
    fun periodComparison(state: AppSnapshot, period: FocusPeriod, interval: DateInterval, projectID: String? = null, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): PeriodComparison {
        val startDate = Time.date(interval.start, zone); val previousDate = if (period == FocusPeriod.week) startDate.minusWeeks(1) else startDate.minusMonths(1)
        val previous = interval(period, Time.start(previousDate, zone), zone)
        var currentRange = interval; var previousRange = previous
        if (now >= interval.start && now < interval.end) {
            currentRange = DateInterval(interval.start, reportingEnd(interval, now, zone))
            val elapsed = java.time.temporal.ChronoUnit.DAYS.between(startDate, Time.date(now, zone)) + 1
            previousRange = DateInterval(previous.start, minOf(previous.end, Time.start(Time.date(previous.start, zone).plusDays(elapsed), zone)))
        }
        return PeriodComparison(currentRange, previousRange, total(state, projectID, currentRange, now), total(state, projectID, previousRange, now))
    }
    fun consistency(state: AppSnapshot, weekStart: Double, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): ConsistencySummary { val week = GoalEngine.week(weekStart, zone); return ConsistencySummary(week, dailySummaries(state, week, now = now, zone = zone).count { it.focusSeconds >= 600 }, state.settings.consistencyTargetDays) }
}
data class StatsDateSelection(val range: StatsDateRange = StatsDateRange.day, val anchor: Double? = null) {
    private fun containing(date: Double, zone: ZoneId): DateInterval? = when (range) { StatsDateRange.day -> Statistics.today(date, zone); StatsDateRange.week -> Statistics.interval(FocusPeriod.week, date, zone); StatsDateRange.month -> Statistics.interval(FocusPeriod.month, date, zone); StatsDateRange.all -> null }
    fun interval(now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): DateInterval? { val current = containing(now, zone) ?: return null; val selected = anchor?.let { containing(it, zone) }; return if (selected != null && selected.start < current.start) selected else current }
    fun isCurrent(now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): Boolean = interval(now, zone)?.start == containing(now, zone)?.start
    fun canMoveForward(now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): Boolean = range != StatsDateRange.all && !isCurrent(now, zone)
    fun setRange(range: StatsDateRange): StatsDateSelection = StatsDateSelection(range)
    fun select(date: Double, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): StatsDateSelection { val selected = containing(date, zone) ?: return this; val current = containing(now, zone) ?: return this; return copy(anchor = selected.start.takeIf { it < current.start }) }
    fun move(offset: Int, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): StatsDateSelection { if (offset !in listOf(-1, 1) || range == StatsDateRange.all || (offset > 0 && !canMoveForward(now, zone))) return this; val start = interval(now, zone)?.start ?: return this; val date = Time.date(start, zone); val moved = when (range) { StatsDateRange.week -> date.plusWeeks(offset.toLong()); StatsDateRange.month -> date.plusMonths(offset.toLong()); else -> date.plusDays(offset.toLong()) }; return select(Time.start(moved, zone), now, zone) }
    fun resetToCurrent(): StatsDateSelection = copy(anchor = null)
    fun reconcile(now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): StatsDateSelection = anchor?.let { select(it, now, zone) } ?: this
}
object StatsPeriodOptions {
    fun months(year: Int, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): List<Double> { val current = Time.date(now, zone).withDayOfMonth(1); if (year <= 0 || year > current.year) return emptyList(); return (1..12).map { LocalDate.of(year, it, 1) }.filter { it <= current }.map { Time.start(it, zone) } }
    fun weeks(year: Int, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): List<DateInterval> { val date = Time.date(now, zone); if (year <= 0 || year > date.get(IsoFields.WEEK_BASED_YEAR)) return emptyList(); var start = LocalDate.of(year, 1, 4).with(java.time.temporal.TemporalAdjusters.previousOrSame(java.time.DayOfWeek.MONDAY)); val current = GoalEngine.week(now, zone).start; val result = mutableListOf<DateInterval>(); while (start.get(IsoFields.WEEK_BASED_YEAR) == year && Time.start(start, zone) <= current) { result += GoalEngine.week(Time.start(start, zone), zone); start = start.plusWeeks(1) }; return result }
    fun years(range: StatsDateRange, selected: Double, earliest: Double? = null, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): IntRange { fun year(value: Double): Int { val date = Time.date(value, zone); return if (range == StatsDateRange.week) date.get(IsoFields.WEEK_BASED_YEAR) else date.year }; return maxOf(1, listOf(selected, earliest ?: now, now).minOf(::year))..year(now) }
}
