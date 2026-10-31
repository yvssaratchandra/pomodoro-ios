package com.jamesblack.pomodoro.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch

@Composable internal fun ProjectsScreen(state: AppSnapshot, now: Double, run: (AppCommand) -> Unit, edit: (String) -> Unit, create: () -> Unit, focus: (String) -> Unit, thoughts: (String) -> Unit, session: (String) -> Unit, platform: PlatformActions) {
    var detailID by rememberSaveable { mutableStateOf<String?>(null) }
    var merge by remember { mutableStateOf<String?>(null) }
    var destination by rememberSaveable { mutableStateOf<String?>(null) }
    var delete by remember { mutableStateOf<String?>(null) }
    var showInactive by rememberSaveable { mutableStateOf(false) }
    val project = state.projects.find { it.id == detailID }
    Page {
        if (project == null) {
            Action("Create Project", onClick = create)
            ProjectStatus.entries.forEach { status ->
                val projects = state.projects.filter { it.status == status }
                if (status != ProjectStatus.ongoing && !showInactive) return@forEach
                if (projects.isNotEmpty()) Section(status.title) { projects.sortedBy { it.name.lowercase() }.forEach { p -> TextButton({ detailID = p.id }, Modifier.fillMaxWidth()) { Column(Modifier.fillMaxWidth()) { Text(p.name, style = MaterialTheme.typography.titleMedium); Hint("${DurationText.summary(Statistics.total(state, p.id))} saved") } } } }
            }
            if (state.projects.any { it.status != ProjectStatus.ongoing }) TextButton({ showInactive = !showInactive }) { Text(if (showInactive) "Hide inactive projects" else "Show inactive projects") }
        } else {
            TextButton({ detailID = null }) { Text("All projects") }
            Text(project.name, style = MaterialTheme.typography.headlineMedium)
            Hint(project.status.title)
            Section("Saved focus") { Text(DurationText.summary(Statistics.total(state, project.id)), style = MaterialTheme.typography.headlineSmall); Hint("${state.sessions.count { it.projectID == project.id }} sessions") }
            Section("This week") {
                val week = GoalEngine.week(now)
                Text(DurationText.summary(Statistics.total(state, project.id, week, now)))
                val goal = GoalEngine.weeklyTarget(project.id, now, state.goalPlan)
                Hint(goal?.let { "of $it min" } ?: "No weekly goal")
            }
            if (project.status == ProjectStatus.ongoing) Action("Use for Focus") { focus(project.id) }
            OutlinedButton({ edit(project.id) }, Modifier.fillMaxWidth()) { Text("Project settings and goals") }
            TextButton({ thoughts(project.id) }) { Text("Review thoughts") }
            TextButton({ platform.pinShortcut(AppRoute.StartFocus(project.id)) }) { Text("Add quick-start shortcut") }
            Section("Recent sessions") {
                val recent = state.sessions.filter { it.projectID == project.id }.sortedByDescending { it.startedAt }.take(5)
                if (recent.isEmpty()) Hint("No saved sessions yet.")
                recent.forEach { SessionListRow(it, project.name, null) { session(it.id) } }
            }
            TextButton({ merge = project.id; destination = null }) { Text("Merge into another project") }
            TextButton({ delete = project.id }) { Text("Delete empty project", color = MaterialTheme.colorScheme.error) }
        }
        if (state.goalPlan.pendingLegacyDailySchedule != null) Section("Assign your previous daily goal") {
            Hint("Choose the project this goal belongs to. It will not be applied to every project.")
            state.projects.forEach { p -> TextButton({ run(AppCommand.AssignLegacyDailyGoal(p.id)) }) { Text("Assign to ${p.name}") } }
            TextButton({ run(AppCommand.DiscardLegacyDailyGoal) }) { Text("Discard previous goal") }
        }
    }
    merge?.let { source -> AlertDialog(onDismissRequest = { merge = null }, title = { Text("Merge project") }, text = { Column(verticalArrangement = Arrangement.spacedBy(12.dp)) { Hint("Sessions and thoughts move to the destination. Its existing goals are kept. Conflicting session plans must be resolved first."); SelectMenu("Destination", state.projects.filter { it.id != source }.map { it.id to it.name }, destination) { destination = it } } }, dismissButton = { TextButton({ merge = null }) { Text("Cancel") } }, confirmButton = { TextButton(enabled = destination != null, onClick = { run(AppCommand.MergeProjects(source, destination!!)); merge = null; detailID = destination }) { Text("Merge") } }) }
    delete?.let { id -> Confirm("Delete empty project?", "Only a project without saved sessions, thoughts, a pending plan, or a running timer can be deleted.", "Delete", { delete = null }) { run(AppCommand.DeleteEmptyProject(id)); delete = null } }
}

@Composable internal fun ProjectEditor(initial: ProjectDraft, state: AppSnapshot, now: Double, dismiss: () -> Unit, save: suspend (ProjectDraft) -> MutationResult) {
    var name by rememberSaveable { mutableStateOf(initial.name) }
    var status by rememberSaveable { mutableStateOf(initial.status.name) }
    var focus by rememberSaveable { mutableIntStateOf(initial.focusMinutes) }
    var shortBreak by rememberSaveable { mutableIntStateOf(initial.shortBreakMinutes) }
    var longBreak by rememberSaveable { mutableIntStateOf(initial.longBreakMinutes) }
    var daily by rememberSaveable { mutableStateOf(initial.dailySchedule) }
    var weekly by rememberSaveable { mutableStateOf(initial.weeklyMinutes) }
    var scheduled by remember { mutableStateOf(initial.scheduledWeeklyEdits) }
    var futureDate by rememberSaveable { mutableStateOf(Time.date(GoalEngine.week(now).end).toString()) }
    var futureGoal by rememberSaveable { mutableStateOf("") }
    var showTimers by rememberSaveable { mutableStateOf(!initial.isNew) }
    var showGoals by rememberSaveable { mutableStateOf(!initial.isNew) }
    var confirming by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val draft = initial.copy(name = name, status = ProjectStatus.valueOf(status), focusMinutes = focus, shortBreakMinutes = shortBreak, longBreakMinutes = longBreak, dailySchedule = daily, weeklyMinutes = weekly, scheduledWeeklyEdits = scheduled)
    val close = { if (!busy) { if (draft.hasChanges) confirming = true else dismiss() } }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.safeDrawingPadding().imePadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(close) { Text("Cancel") }; Text(if (initial.isNew) "New project" else "Project settings", Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    TextButton(enabled = !busy && name.isNotBlank() && SessionText.count(name) <= 100, onClick = { scope.launch { busy = true; when (val result = save(draft)) { MutationResult.Success -> dismiss(); is MutationResult.Failure -> error = result.message }; busy = false } }) { Text("Save") }
                }
                Page {
                    OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("Project name") }, singleLine = true, supportingText = { Text("${SessionText.count(name)} / 100") })
                    if (!initial.isNew) SelectMenu("Status", ProjectStatus.entries.map { it.name to it.title }, status) { status = it }
                    TextButton({ showTimers = !showTimers }) { Text(if (showTimers) "Hide timer settings" else "Timer settings") }
                    if (showTimers) Section("Timer settings") { MinuteControl("Focus", focus, 10, 60) { focus = it }; MinuteControl("Short break", shortBreak, 1, 60) { shortBreak = it }; MinuteControl("Long break", longBreak, 1, 60) { longBreak = it } }
                    TextButton({ showGoals = !showGoals }) { Text(if (showGoals) "Hide goals" else "Set daily and weekly goals") }
                    if (showGoals) {
                        Section("Daily goal") {
                            Hint("Changes take effect today. Earlier days retain their recorded goals.")
                            if (daily == null) { Hint("No recorded daily goal"); TextButton({ daily = List(7) { 60 } }) { Text("Set daily goals") } }
                            daily?.let { schedule ->
                                MinuteControl("Same every day", schedule.first(), 0, 1440) { minutes -> daily = List(7) { minutes } }
                                listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday").forEachIndexed { day, label -> MinuteControl(label, schedule[day], 0, 1440) { minutes -> daily = schedule.mapIndexed { i, value -> if (i == day) minutes else value } } }
                            }
                        }
                        Section("Weekly goal") {
                            Hint("Current-week changes take effect from ${initial.createdWeek.date()}.")
                            Row(verticalAlignment = Alignment.CenterVertically) { Switch(weekly != null, { weekly = if (it) 300 else null }); Text("Weekly goal") }
                            weekly?.let { value -> MinuteControl("Minutes per week", value, 1, 10080) { weekly = it } }
                        }
                        Section("Scheduled weekly changes") {
                            Hint("Schedule a Monday after the current week. Leave minutes blank to turn the goal off.")
                            OutlinedTextField(futureDate, { futureDate = it }, label = { Text("Monday (YYYY-MM-DD)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            OutlinedTextField(futureGoal, { futureGoal = it.filter(Char::isDigit).take(5) }, label = { Text("Weekly minutes, or blank for off") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                            val date = runCatching { java.time.LocalDate.parse(futureDate) }.getOrNull()
                            val valid = date != null && date.dayOfWeek == java.time.DayOfWeek.MONDAY && LocalDay(date) > initial.createdWeek && (futureGoal.isBlank() || futureGoal.toIntOrNull()?.let { it in 1..10080 } == true)
                            TextButton(enabled = valid, onClick = { scheduled = scheduled + (LocalDay(date!!) to ScheduledWeeklyEdit.Set(futureGoal.toIntOrNull())) }) { Text("Add scheduled change") }
                            val current = initial.baseline.weeklyRevisions.filter { it.effectiveFrom > initial.createdWeek }.associate { it.effectiveFrom to it.minutes }.toMutableMap()
                            scheduled.forEach { (day, edit) -> when (edit) { is ScheduledWeeklyEdit.Set -> current[day] = edit.minutes; ScheduledWeeklyEdit.Cancel -> current.remove(day) } }
                            current.toSortedMap().forEach { (day, minutes) -> Row(verticalAlignment = Alignment.CenterVertically) { Text("${day.date()}: ${minutes?.let { "$it min" } ?: "Off"}", Modifier.weight(1f)); TextButton({ scheduled = scheduled + (day to ScheduledWeeklyEdit.Cancel) }) { Text("Cancel change") } } }
                        }
                    }
                    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                }
            }
        }
    }
    if (confirming) AlertDialog(onDismissRequest = { confirming = false }, title = { Text("Discard changes?") }, dismissButton = { TextButton({ confirming = false }) { Text("Keep editing") } }, confirmButton = { TextButton(dismiss) { Text("Discard") } })
}
