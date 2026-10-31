package com.jamesblack.pomodoro.core.store

import com.jamesblack.pomodoro.core.*
import java.time.ZoneId

data class ProjectBaseline(val project: Project, val dailySchedule: List<Int>?, val weeklyMinutes: Int?, val dailyRevisions: List<ProjectDailyGoalRevision>, val weeklyRevisions: List<ProjectWeeklyGoalRevision>)
sealed interface ScheduledWeeklyEdit { data class Set(val minutes: Int?) : ScheduledWeeklyEdit; data object Cancel : ScheduledWeeklyEdit }
data class ProjectDraft(val projectID: String, val isNew: Boolean, val createdOn: LocalDay, val createdWeek: LocalDay, val baseline: ProjectBaseline, val name: String, val status: ProjectStatus, val focusMinutes: Int, val shortBreakMinutes: Int, val longBreakMinutes: Int, val dailySchedule: List<Int>?, val weeklyMinutes: Int?, val scheduledWeeklyEdits: Map<LocalDay, ScheduledWeeklyEdit> = emptyMap()) {
    val hasChanges: Boolean get() = name.trim() != baseline.project.name || status != baseline.project.status || focusMinutes != baseline.project.preferredFocusMinutes || shortBreakMinutes != baseline.project.shortBreakMinutes || longBreakMinutes != baseline.project.longBreakMinutes || dailySchedule != baseline.dailySchedule || weeklyMinutes != baseline.weeklyMinutes || scheduledWeeklyEdits.isNotEmpty()
    companion object {
        fun from(snapshot: AppSnapshot, projectID: String? = null, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault()): ProjectDraft {
            val project = if (projectID == null) Project(name = "", focusMinutes = snapshot.settings.defaultFocusMinutes, shortBreakMinutes = snapshot.settings.defaultShortBreakMinutes, longBreakMinutes = snapshot.settings.defaultLongBreakMinutes, createdAt = now) else requireNotNull(snapshot.projects.find { it.id == projectID }) { "Project unavailable." }
            val daily = GoalEngine.dailySchedule(project.id, now, snapshot.goalPlan, zone)
            val weekly = GoalEngine.weeklyTarget(project.id, now, snapshot.goalPlan, zone)
            return ProjectDraft(project.id, projectID == null, LocalDay.at(now, zone), LocalDay.at(GoalEngine.week(now, zone).start, zone), ProjectBaseline(project, daily, weekly, snapshot.goalPlan.dailyProjectRevisions.filter { it.projectID == project.id }, snapshot.goalPlan.weeklyProjectRevisions.filter { it.projectID == project.id }), project.name, project.status, project.preferredFocusMinutes, project.shortBreakMinutes, project.longBreakMinutes, daily, weekly)
        }
    }
}

internal fun saveProjectDraft(state: AppSnapshot, draft: ProjectDraft, now: Double, zone: ZoneId): AppSnapshot {
    if (!draft.hasChanges) return state
    val b = draft.baseline
    val name = requireNotNull(SessionText.normalize(draft.name, 100)) { "Enter a project name." }
    require(draft.focusMinutes in 10..60 && draft.shortBreakMinutes in 1..60 && draft.longBreakMinutes in 1..60) { "Check the project durations." }
    val week = LocalDay.at(GoalEngine.week(now, zone).start, zone)
    val dailyChanged = draft.dailySchedule != b.dailySchedule
    val weeklyChanged = draft.weeklyMinutes != b.weeklyMinutes || draft.scheduledWeeklyEdits.isNotEmpty()
    require(!dailyChanged || draft.createdOn == LocalDay.at(now, zone)) { "The date changed while editing. Reopen project settings." }
    require(!weeklyChanged || draft.createdWeek == week) { "The week changed while editing. Reopen project settings." }
    val current = state.projects.find { it.id == draft.projectID }
    val project = if (draft.isNew) {
        require(current == null) { "This project already exists." }
        Project(id = draft.projectID, name = name, status = draft.status, focusMinutes = draft.focusMinutes, shortBreakMinutes = draft.shortBreakMinutes, longBreakMinutes = draft.longBreakMinutes, createdAt = now)
    } else {
        requireNotNull(current) { "This project is no longer available." }
        fun <T> conflict(proposed: T, original: T, actual: T) { require(proposed == original || actual == original || proposed == actual) { "The project changed. Reopen project settings." } }
        conflict(name, b.project.name, current.name); conflict(draft.status, b.project.status, current.status)
        conflict(draft.focusMinutes, b.project.preferredFocusMinutes, current.preferredFocusMinutes)
        conflict(draft.shortBreakMinutes, b.project.shortBreakMinutes, current.shortBreakMinutes); conflict(draft.longBreakMinutes, b.project.longBreakMinutes, current.longBreakMinutes)
        require(!dailyChanged || state.goalPlan.dailyProjectRevisions.filter { it.projectID == current.id } == b.dailyRevisions) { "This project's daily goal changed. Reopen project settings." }
        require(!weeklyChanged || state.goalPlan.weeklyProjectRevisions.filter { it.projectID == current.id } == b.weeklyRevisions) { "This project's weekly goals changed. Reopen project settings." }
        require(state.activeTimer?.projectID != current.id || draft.status == current.status) { "End this project's timer before changing its status." }
        current.copy(name = if (name != b.project.name) name else current.name, status = if (draft.status != b.project.status) draft.status else current.status,
            focusMinutes = if (draft.focusMinutes != b.project.preferredFocusMinutes) draft.focusMinutes else current.focusMinutes,
            lastFocusMinutes = if (draft.focusMinutes != b.project.preferredFocusMinutes) null else current.lastFocusMinutes,
            shortBreakMinutes = if (draft.shortBreakMinutes != b.project.shortBreakMinutes) draft.shortBreakMinutes else current.shortBreakMinutes,
            longBreakMinutes = if (draft.longBreakMinutes != b.project.longBreakMinutes) draft.longBreakMinutes else current.longBreakMinutes)
    }
    var plan = state.goalPlan
    if (dailyChanged && draft.dailySchedule != null) plan = GoalEngine.setDaily(plan, project.id, draft.dailySchedule, now, zone)
    if (draft.weeklyMinutes != b.weeklyMinutes) plan = GoalEngine.setWeekly(plan, project.id, draft.weeklyMinutes, now, zone)
    draft.scheduledWeeklyEdits.toSortedMap().forEach { (day, edit) ->
        require(day > week) { "Only future weekly changes can be edited here." }
        plan = when (edit) {
            is ScheduledWeeklyEdit.Set -> GoalEngine.setWeekly(plan, project.id, edit.minutes, now, zone, Time.start(day.date(), zone))
            ScheduledWeeklyEdit.Cancel -> plan.copy(weeklyProjectRevisions = plan.weeklyProjectRevisions.filterNot { it.projectID == project.id && it.effectiveFrom == day })
        }
    }
    return state.copy(projects = if (draft.isNew) state.projects + project else state.projects.map { if (it.id == project.id) project else it }, goalPlan = plan)
}
