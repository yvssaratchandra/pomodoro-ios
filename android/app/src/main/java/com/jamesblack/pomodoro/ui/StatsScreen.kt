package com.jamesblack.pomodoro.ui

import android.app.DatePickerDialog
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch

@Composable internal fun StatsScreen(state: AppSnapshot, now: Double, openSession: (String) -> Unit, editProject: (String) -> Unit) {
    var rangeName by rememberSaveable { mutableStateOf(StatsDateRange.day.name) }
    var anchor by rememberSaveable { mutableStateOf<Double?>(null) }
    var projectID by rememberSaveable { mutableStateOf<String?>(null) }
    var drillDay by rememberSaveable { mutableStateOf<Double?>(null) }
    val range = StatsDateRange.valueOf(rangeName)
    val selection = StatsDateSelection(range, anchor)
    val interval = selection.interval(now)
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    val sessions = state.sessions.filter { (projectID == null || it.projectID == projectID) && (interval == null || Statistics.overlap(it.startedAt, it.endedAt, interval) > 0 || (it.duration == 0.0 && it.startedAt >= interval.start && it.startedAt < interval.end)) }.sortedByDescending { it.startedAt }
    Page {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) { StatsDateRange.entries.forEach { option -> FilterChip(selected = range == option, onClick = { rangeName = option.name; anchor = null; drillDay = null }, label = { Text(option.title) }) } }
        SelectMenu("Project", listOf("" to "All projects") + state.projects.map { it.id to it.name }, projectID ?: "") { projectID = it.takeIf(String::isNotEmpty) }
        if (interval != null) Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton({ anchor = selection.move(-1, now).anchor; drillDay = null }) { Text("Previous") }
            TextButton(modifier = Modifier.weight(1f), onClick = { val date = Time.date(interval.start); DatePickerDialog(context, { _, year, month, day -> anchor = selection.select(Time.start(java.time.LocalDate.of(year, month + 1, day), zone), now).anchor; drillDay = null }, date.year, date.monthValue - 1, date.dayOfMonth).apply { datePicker.maxDate = Time.toInstant(now).toEpochMilli() }.show() }) { Text(if (selection.isCurrent(now)) when (range) { StatsDateRange.day -> "Today"; StatsDateRange.week -> "This week"; StatsDateRange.month -> "This month"; else -> "All" } else periodLabel(interval)) }
            TextButton(enabled = selection.canMoveForward(now), onClick = { anchor = selection.move(1, now).anchor; drillDay = null }) { Text("Next") }
        }
        if (!selection.isCurrent(now) && range != StatsDateRange.all) TextButton({ anchor = null; drillDay = null }) { Text("Return to current ${range.title.lowercase()}") }
        Section("Focus time") {
            Text(DurationText.summary(Statistics.total(state, projectID, interval, now)), style = MaterialTheme.typography.headlineLarge)
            if (Statistics.hasFocusInProgress(state, projectID, interval, now)) Hint("1 session in progress · not included yet")
            Text("${sessions.count { it.outcome == SessionOutcome.completed }} completed · ${sessions.count { it.outcome == SessionOutcome.interrupted }} ended early")
            if (projectID != null && range == StatsDateRange.day) {
                val target = GoalEngine.dailyTarget(projectID!!, interval!!.start, state.goalPlan)
                Hint(when (target) { null -> "No recorded goal"; 0 -> "Rest day"; else -> "Daily goal: $target min" })
                TextButton({ editProject(projectID!!) }) { Text("Edit project goals") }
            }
        }
        if (interval != null && range.period != null) {
            val summary = Statistics.periodSummary(state, interval, projectID, now)
            val comparison = Statistics.periodComparison(state, range.period!!, interval, projectID, now)
            Section("Daily focus") {
                Hint("Average ${DurationText.summary(summary.averageSeconds)} per elapsed day")
                val maximum = summary.days.maxOfOrNull { it.focusSeconds }?.coerceAtLeast(60.0) ?: 60.0
                summary.days.forEach { day ->
                    if (!day.isFuture) Column(Modifier.fillMaxWidth().clickable { drillDay = day.date }.padding(vertical = 4.dp)) {
                        Row { Text(Time.date(day.date).format(DateTimeFormatter.ofPattern("EEE d MMM")), Modifier.weight(1f)); Text(DurationText.summary(day.focusSeconds)) }
                        LinearProgressIndicator(progress = { (day.focusSeconds / maximum).toFloat().coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth().padding(top = 6.dp))
                    }
                }
                Hint("Tap a day to see its sessions.")
            }
            Section("Comparison") {
                Text("${if (comparison.delta >= 0) "+" else "−"}${DurationText.summary(kotlin.math.abs(comparison.delta))} compared with previous ${range.title.lowercase()}")
                comparison.percentage?.let { Hint("${"%.0f".format(kotlin.math.abs(it))}% ${if (it >= 0) "more" else "less"}") }
                Hint("This period: ${periodLabel(comparison.current)}")
                Hint("Previous period: ${periodLabel(comparison.previous)}")
                Hint(if (interval.end > now) "Compared with the same calendar days in the previous period, including the full matching day." else "Compared with the full previous period.")
            }
            if (summary.projects.isNotEmpty()) Section("Projects") { summary.projects.forEach { project -> Row { Text(project.name, Modifier.weight(1f)); Text(DurationText.summary(project.seconds)) } } }
        }
        Section("Consistency") {
            val current = Statistics.consistency(state, now, now)
            Text("${current.focusedDays} of ${current.targetDays} days this week", style = MaterialTheme.typography.titleLarge)
            Hint("A focused day has at least 10 minutes of saved focus. Active sessions are included after saving.")
            (1..8).forEach { offset -> val date = Time.date(current.week.start).minusWeeks(offset.toLong()); val week = Statistics.consistency(state, Time.start(date, zone), now); Row { Text("Week of $date", Modifier.weight(1f)); Text("${week.focusedDays} focused days") } }
        }
        val historyInterval = drillDay?.let { Statistics.today(it) }
        val visibleSessions = if (historyInterval == null) sessions else sessions.filter { Statistics.overlap(it.startedAt, it.endedAt, historyInterval) > 0 || it.startedAt >= historyInterval.start && it.startedAt < historyInterval.end }
        Section(if (drillDay == null) "Sessions" else "Sessions · ${Time.date(drillDay!!)}") {
            if (drillDay != null) TextButton({ drillDay = null }) { Text("Show whole period") }
            if (visibleSessions.isEmpty()) Hint("No saved sessions for this selection.")
            visibleSessions.groupBy { Time.date(it.startedAt) }.forEach { (day, entries) ->
                Text(day.format(DateTimeFormatter.ofPattern("EEE d MMM yyyy")), style = MaterialTheme.typography.titleSmall)
                entries.forEach { session -> SessionListRow(session, state.projects.find { it.id == session.projectID }?.name ?: "Project", historyInterval) { openSession(session.id) } }
            }
        }
    }
}
internal fun periodLabel(interval: DateInterval): String { val start = Time.date(interval.start); val end = Time.date(interval.end - 1); return if (start == end) start.toString() else "$start – $end" }
@Composable internal fun SessionListRow(session: FocusSession, project: String, day: DateInterval?, open: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = open).padding(vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(project, style = MaterialTheme.typography.titleMedium)
        SessionPlanText.items(session.intention).firstOrNull()?.let { Text(it, maxLines = 2) }
        Hint("${Time.toInstant(session.startedAt).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("HH:mm"))} · ${DurationText.summary(session.duration)}${if (session.outcome == SessionOutcome.interrupted) " · Ended early" else ""}")
        day?.let { Hint("This day: ${DurationText.summary(Statistics.overlap(session.startedAt, session.endedAt, it))}") }
    }
}

@Composable internal fun SessionDetail(state: AppSnapshot, id: String, dismiss: () -> Unit, execute: suspend (AppCommand) -> MutationResult) {
    val session = state.sessions.find { it.id == id }
    var note by remember { mutableStateOf<NoteRequest?>(null) }
    var deleting by remember { mutableStateOf(false) }
    var promote by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Dialog(onDismissRequest = dismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.safeDrawingPadding()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) { Text("Session", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge); TextButton(dismiss) { Text("Done") } }
                Page {
                    if (session == null) Hint("This session has been removed.") else {
                        Text(state.projects.find { it.id == session.projectID }?.name ?: "Project", style = MaterialTheme.typography.headlineSmall)
                        Text(DurationText.summary(session.duration), style = MaterialTheme.typography.headlineLarge)
                        Hint("${Time.date(session.startedAt)} · ${session.outcome.name.replaceFirstChar { it.uppercase() }}")
                        Hint("Planned ${DurationText.summary(session.plannedSeconds.toDouble())}")
                        Section("Session plan") { session.intention?.let { Text(it) } ?: Hint("No session plan"); TextButton({ note = NoteRequest("Session plan", session.intention.orEmpty()) { AppCommand.EditIntention(id, false, it) } }) { Text(if (session.intention == null) "Add session plan" else "Edit session plan") } }
                        Section("Next step") {
                            session.nextStep?.let { Text(it) } ?: Hint("No next step")
                            TextButton({ note = NoteRequest("Next step", session.nextStep.orEmpty()) { AppCommand.SaveNextStep(id, it, false) } }) { Text(if (session.nextStep == null) "Add next step" else "Edit next step") }
                            if (session.nextStep != null) TextButton({ promote = true }) { Text("Use for next session") }
                        }
                        TextButton({ deleting = true }) { Text("Delete Session", color = MaterialTheme.colorScheme.error) }
                        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                    }
                }
            }
        }
    }
    note?.let { request -> key(request) { TextEditor(request.title, request.text, request.limit, { note = null }) { execute(request.command(it)) } } }
    if (deleting) Confirm("Delete session?", "The saved focus time will be removed from your statistics. Thoughts remain saved.", "Delete", { deleting = false }) { scope.launch { when (val result = execute(AppCommand.DeleteSessions(setOf(id)))) { MutationResult.Success -> dismiss(); is MutationResult.Failure -> error = result.message }; deleting = false } }
    if (promote && session != null) Confirm("Replace next-session plan?", "This next step becomes the project's plan for its next focus session.", "Replace plan", { promote = false }) { scope.launch { when (val result = execute(AppCommand.SaveNextStep(id, session.nextStep.orEmpty(), true))) { is MutationResult.Failure -> error = result.message; else -> {} }; promote = false } }
}
