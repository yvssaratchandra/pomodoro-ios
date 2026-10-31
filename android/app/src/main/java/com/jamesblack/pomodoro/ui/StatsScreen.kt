package com.jamesblack.pomodoro.ui

import android.app.DatePickerDialog
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.*
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
    var details by rememberSaveable { mutableStateOf(false) }
    var consistency by rememberSaveable { mutableStateOf(false) }
    var fullHistory by rememberSaveable { mutableStateOf(false) }
    var picker by remember { mutableStateOf(false) }
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
            TextButton(modifier = Modifier.weight(1f), onClick = { picker = true }) { Text(if (selection.isCurrent(now)) when (range) { StatsDateRange.day -> "Today"; StatsDateRange.week -> "This week"; StatsDateRange.month -> "This month"; else -> "All" } else periodLabel(interval)) }
            TextButton(enabled = selection.canMoveForward(now), onClick = { anchor = selection.move(1, now).anchor; drillDay = null }) { Text("Next") }
        }
        if (!selection.isCurrent(now) && range != StatsDateRange.all) TextButton({ anchor = null; drillDay = null }) { Text("Return to current ${range.title.lowercase()}") }
        Section("Focus time") {
            Text(DurationText.summary(Statistics.total(state, projectID, interval, now)), style = MaterialTheme.typography.headlineLarge)
            if (Statistics.hasFocusInProgress(state, projectID, interval, now)) Hint("1 session in progress · not included yet")

            if (projectID != null && range == StatsDateRange.day) {
                val target = GoalEngine.dailyTarget(projectID!!, interval!!.start, state.goalPlan)
                Hint(when (target) { null -> "No recorded goal"; 0 -> "Rest day"; else -> "Daily goal: $target min" })
                TextButton({ editProject(projectID!!) }) { Text("Edit project goals") }
            }
            if (projectID != null && range == StatsDateRange.week) GoalEngine.weeklyTarget(projectID!!, interval!!.start, state.goalPlan)?.let { Hint("Weekly goal: $it min") }
        }
        if (interval != null && range.period != null) {
            val summary = remember(state.sessions, state.goalPlan, state.projects, interval, projectID, now.toLong() / 60) { Statistics.periodSummary(state, interval, projectID, now) }
            val comparison = Statistics.periodComparison(state, range.period!!, interval, projectID, now)
            Section("Daily focus") {
                val maximum = summary.days.maxOfOrNull { it.focusSeconds }?.coerceAtLeast(60.0) ?: 60.0
                Row(Modifier.fillMaxWidth().height(155.dp).semantics { contentDescription = "Daily focus chart. Open Details for values and sessions." }, horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.Bottom) {
                    summary.days.forEach { day -> Box(Modifier.weight(1f).fillMaxHeight((day.focusSeconds / maximum).toFloat().coerceIn(.01f, 1f)).background(if (day.isFuture) MaterialTheme.colorScheme.outline.copy(alpha = .35f) else Indigo)) }
                }
                Hint("${DurationText.summary(kotlin.math.abs(comparison.delta))} ${if (comparison.delta >= 0) "more" else "less"} than last ${range.title.lowercase()}${if (interval.end > now) " so far" else ""}")
                TextButton({ details = true }) { Text("Details") }
            }
            if (details) Dialog(onDismissRequest = { details = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) { Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { Page(Modifier.safeDrawingPadding()) { Section("Period details") {
                TextButton({ details = false }) { Text("Close Details") }
                summary.days.filter { !it.isFuture }.forEach { day -> TextButton({ drillDay = day.date; fullHistory = true; details = false }) { Text("${Time.date(day.date)} · ${DurationText.summary(day.focusSeconds)}") } }
                Text("Daily average: ${DurationText.summary(summary.averageSeconds)}")
                Text("${summary.completedCount} completed · ${summary.interruptedCount} ended early")
                Hint("This period: ${periodLabel(comparison.current)} · ${DurationText.summary(comparison.currentSeconds)}")
                Hint("Previous period: ${periodLabel(comparison.previous)} · ${DurationText.summary(comparison.previousSeconds)}")
                comparison.percentage?.let { Hint("Change: ${"%+.1f".format(it)}%") }
                Hint(if (interval.end > now) "Compared with the same calendar days in the previous period, including the full matching day." else "Compared with the full previous period.")
                if (projectID == null) summary.projects.forEach { project -> Row { Text(project.name, Modifier.weight(1f)); Text(DurationText.summary(project.seconds)) } }
                if (summary.days.any { it.targetMinutes == null }) Hint("Older dates may not have a recorded goal.")
            } } } }
        }
        TextButton({ consistency = !consistency }) { Text("Consistency") }
        if (consistency) Dialog(onDismissRequest = { consistency = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) { Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) { Page(Modifier.safeDrawingPadding()) { Section("Consistency") {
            TextButton({ consistency = false }) { Text("Done") }
            val current = Statistics.consistency(state, now, now)
            Text("${current.focusedDays} of ${current.targetDays} days this week", style = MaterialTheme.typography.titleLarge)
            Hint("A focused day has at least 10 minutes of saved focus. Active sessions are included after saving.")
            (1..8).forEach { offset -> val date = Time.date(current.week.start).minusWeeks(offset.toLong()); val week = Statistics.consistency(state, Time.start(date, zone), now); Row { Text("Week of $date", Modifier.weight(1f)); Text("${week.focusedDays} focused days") } }
        } } } }
        val historyInterval = drillDay?.let { Statistics.today(it) }
        val allSessions = if (historyInterval == null) sessions else sessions.filter { Statistics.overlap(it.startedAt, it.endedAt, historyInterval) > 0 || it.startedAt >= historyInterval.start && it.startedAt < historyInterval.end }
        val visibleSessions = if (fullHistory) allSessions else allSessions.take(5)
        Section(if (drillDay == null) "Recent sessions" else "Sessions · ${Time.date(drillDay!!)}") {
            if (drillDay != null) TextButton({ drillDay = null; fullHistory = false }) { Text("Show whole period") }
            if (visibleSessions.isEmpty()) Hint("No saved sessions for this selection.")
            if (!fullHistory && allSessions.size > 5) TextButton({ fullHistory = true }) { Text("View all sessions") }
            visibleSessions.groupBy { Time.date(it.startedAt) }.forEach { (day, entries) ->
                Text(day.format(DateTimeFormatter.ofPattern("EEE d MMM yyyy")), style = MaterialTheme.typography.titleSmall)
                entries.forEach { session -> SessionListRow(session, state.projects.find { it.id == session.projectID }?.name ?: "Project", historyInterval) { openSession(session.id) } }
            }
        }
    }
    if (picker) StatsPeriodPicker(range, interval?.start ?: now, state.sessions.minOfOrNull { it.startedAt }, now, { picker = false }) { date -> anchor = selection.select(date, now).anchor; drillDay = null; fullHistory = false; picker = false }

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

@Composable internal fun SessionDetail(state: AppSnapshot, id: String, dismiss: () -> Unit, execute: suspend (AppCommand) -> MutationResult, edit: (NoteRequest) -> Unit) {
    val session = state.sessions.find { it.id == id }
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
                        Section("Session plan") { session.intention?.let { Text(it) } ?: Hint("No session plan"); TextButton({ edit(NoteRequest("Session plan", session.intention.orEmpty()) { AppCommand.EditIntention(id, false, it) }) }) { Text(if (session.intention == null) "Add session plan" else "Edit session plan") } }
                        Section("Next step") {
                            session.nextStep?.let { Text(it) } ?: Hint("No next step")
                            TextButton({ edit(NoteRequest("Next step", session.nextStep.orEmpty()) { AppCommand.SaveNextStep(id, it, false) }) }) { Text(if (session.nextStep == null) "Add next step" else "Edit next step") }
                            if (session.nextStep != null) TextButton({ promote = true }) { Text("Use for next session") }
                        }
                        TextButton({ deleting = true }) { Text("Delete Session", color = MaterialTheme.colorScheme.error) }
                        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                    }
                }
            }
        }
    }
    if (deleting) Confirm("Delete session?", "The saved focus time will be removed from your statistics. Thoughts remain saved.", "Delete", { deleting = false }) { scope.launch { when (val result = execute(AppCommand.DeleteSessions(setOf(id)))) { MutationResult.Success -> dismiss(); is MutationResult.Failure -> error = result.message }; deleting = false } }
    if (promote && session != null) Confirm("Replace next-session plan?", "This next step becomes the project's plan for its next focus session.", "Replace plan", { promote = false }) { scope.launch { when (val result = execute(AppCommand.SaveNextStep(id, session.nextStep.orEmpty(), true))) { is MutationResult.Failure -> error = result.message; else -> {} }; promote = false } }
}

@Composable internal fun StatsPeriodPicker(range: StatsDateRange, selected: Double, earliest: Double?, now: Double, dismiss: () -> Unit, choose: (Double) -> Unit) {
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    var year by rememberSaveable { mutableIntStateOf(Time.date(selected).year) }
    if (range == StatsDateRange.day) {
        DisposableEffect(Unit) {
            val date = Time.date(selected)
            val dialog = DatePickerDialog(context, { _, y, m, d -> choose(Time.start(java.time.LocalDate.of(y, m + 1, d), zone)) }, date.year, date.monthValue - 1, date.dayOfMonth)
            dialog.datePicker.maxDate = Time.toInstant(now).toEpochMilli(); dialog.setOnDismissListener { dismiss() }; dialog.show()
            onDispose { dialog.dismiss() }
        }
    } else Dialog(onDismissRequest = dismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.safeDrawingPadding()) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text("Choose a ${range.title.lowercase()}", Modifier.weight(1f).padding(20.dp), style = MaterialTheme.typography.titleLarge); TextButton(dismiss) { Text("Done") } }
                Page {
                    val years = StatsPeriodOptions.years(range, selected, earliest, now)
                    SelectMenu("Year", years.reversed().map { it.toString() to it.toString() }, year.toString()) { year = it.toInt() }
                    if (range == StatsDateRange.week) StatsPeriodOptions.weeks(year, now).reversed().forEach { week -> TextButton({ choose(week.start) }, Modifier.fillMaxWidth()) { Text(periodLabel(week)) } }
                    else StatsPeriodOptions.months(year, now).chunked(3).forEach { row -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) { row.forEach { month -> OutlinedButton({ choose(month) }, Modifier.weight(1f).heightIn(min = 64.dp)) { Text(Time.date(month).month.getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.getDefault())) } }; repeat(3 - row.size) { Spacer(Modifier.weight(1f)) } } }
                }
            }
        }
    }
}
