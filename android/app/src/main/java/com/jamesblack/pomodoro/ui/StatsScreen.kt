package com.jamesblack.pomodoro.ui

import android.app.DatePickerDialog
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.ChevronLeft
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.History
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.geometry.Offset
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
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
    BackHandler(fullHistory && !details && !consistency) { fullHistory = false; drillDay = null }
    LaunchedEffect(state.projects, projectID) { if (projectID != null && state.projects.none { it.id == projectID }) projectID = null }
    val range = StatsDateRange.valueOf(rangeName)
    val selection = StatsDateSelection(range, anchor)
    val interval = selection.interval(now)
    val zone = ZoneId.systemDefault()
    val sessions = state.sessions.filter { (projectID == null || it.projectID == projectID) && (interval == null || Statistics.overlap(it.startedAt, it.endedAt, interval) > 0 || (it.duration == 0.0 && it.startedAt >= interval.start && it.startedAt < interval.end)) }.sortedByDescending { it.startedAt }

    Page(horizontalPadding = 16.dp, verticalSpacing = 32.dp, header = {
        ScreenHeader(
            "Stats",
            largeTitle = true,
            leading = { StatsProjectFilter(projectID, state) { projectID = it } },
            trailing = {
                IconButton(onClick = { consistency = true }, modifier = Modifier.size(48.dp)) {
                    Icon(Icons.Outlined.CalendarMonth, "Consistency", modifier = Modifier.size(24.dp))
                }
            }
        )
    }) {
        Surface(shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                SegmentedSelector(
                    options = StatsDateRange.entries.map { it.name to it.title },
                    selected = range.name,
                    onSelect = { rangeName = it; anchor = null; drillDay = null; fullHistory = false }
                )
                if (interval != null) {
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .5f))
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        IconButton(
                            onClick = { anchor = selection.move(-1, now).anchor; drillDay = null },
                            modifier = Modifier.size(48.dp)
                        ) { Icon(Icons.Outlined.ChevronLeft, "Previous ${range.title.lowercase()}", modifier = Modifier.size(24.dp)) }
                        TextButton(
                            modifier = Modifier.weight(1f).heightIn(min = 48.dp),
                            onClick = { picker = true }
                        ) {
                            Text(
                                periodTitle(selection, interval, range, now),
                                textAlign = TextAlign.Center,
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp)
                            )
                            Spacer(Modifier.width(4.dp))
                            Icon(
                                Icons.Outlined.CalendarMonth,
                                contentDescription = "Choose ${range.title.lowercase()}",
                                modifier = Modifier.size(12.dp)
                            )
                        }
                        IconButton(
                            enabled = selection.canMoveForward(now),
                            onClick = { anchor = selection.move(1, now).anchor; drillDay = null },
                            modifier = Modifier.size(48.dp)
                        ) { Icon(Icons.Outlined.ChevronRight, "Next ${range.title.lowercase()}", modifier = Modifier.size(24.dp)) }
                    }
                    if (!selection.isCurrent(now) && range != StatsDateRange.all) {
                        TextButton(onClick = { anchor = null; drillDay = null; fullHistory = false }) {
                            Text("Return to current ${range.title.lowercase()}")
                        }
                    }
                }
            }
        }
        Surface(shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "Focus time",
                    style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    DurationText.summary(Statistics.total(state, projectID, interval, now)),
                    style = MaterialTheme.typography.headlineLarge.copy(fontSize = 34.sp, lineHeight = 40.sp),
                    fontWeight = FontWeight.Bold
                )
                if (Statistics.hasFocusInProgress(state, projectID, interval, now)) {
                    Text(
                        "1 session in progress · not included yet",
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
        if (projectID != null && range == StatsDateRange.day && interval != null) {
            val target = GoalEngine.dailyTarget(projectID!!, interval.start, state.goalPlan)
            CompositionLocalProvider(LocalTextStyle provides MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp)) {
                GroupedRow(
                    label = when (target) { null -> "Daily goal"; 0 -> "Rest day"; else -> "Daily goal" },
                    value = when (target) { null -> "No recorded goal"; 0 -> null; else -> "$target min" },
                    onClick = { editProject(projectID!!) }
                )
            }
        }
        if (projectID != null && range == StatsDateRange.week && interval != null) {
            GoalEngine.weeklyTarget(projectID!!, interval.start, state.goalPlan)?.let { target ->
                CompositionLocalProvider(LocalTextStyle provides MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp)) {
                    GroupedRow(label = "Weekly goal", value = "$target min")
                }
            }
        }
        if (interval != null && range.period != null) {
            val summary = remember(state.sessions, state.goalPlan, state.projects, interval, projectID, now.toLong() / 60) {
                Statistics.periodSummary(state, interval, projectID, now)
            }
            val comparison = Statistics.periodComparison(state, range.period!!, interval, projectID, now)
            Surface(shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                    FocusChart(summary.days) { day -> drillDay = day.date; fullHistory = true }
                    val periodName = range.title.lowercase()
                    val comparisonText = when {
                        comparison.delta == 0.0 -> "Same as last $periodName${if (interval.end > now) " so far" else ""}"
                        else -> "${DurationText.summary(kotlin.math.abs(comparison.delta))} ${if (comparison.delta > 0) "more" else "less"} than last $periodName${if (interval.end > now) " so far" else ""}"
                    }
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .5f))
                    Text(
                        comparisonText,
                        modifier = Modifier.padding(vertical = 16.dp),
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .5f))
                    GroupedRow("Details", onClick = { details = true })
                }
            }
            if (details) Dialog(onDismissRequest = { details = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    Page(
                        modifier = Modifier.safeDrawingPadding(),
                        header = { ScreenHeader("Period details", leading = { TextButton({ details = false }) { Text("Done") } }) }
                    ) {
                        Section("Daily breakdown") {
                            summary.days.filter { !it.isFuture }.forEach { day ->
                                GroupedRow(
                                    label = Time.date(day.date).toString(),
                                    value = DurationText.summary(day.focusSeconds),
                                    onClick = { drillDay = day.date; fullHistory = true; details = false }
                                )
                            }
                        }
                        Section("Overview") {
                            GroupedRow(label = "Daily average", value = DurationText.summary(summary.averageSeconds))
                            GroupedRow(label = "Completed", value = "${summary.completedCount}")
                            GroupedRow(label = "Ended early", value = "${summary.interruptedCount}")
                        }
                        Section("Comparison") {
                            GroupedRow(label = "This period · ${periodLabel(comparison.current)}", value = DurationText.summary(comparison.currentSeconds))
                            GroupedRow(label = "Previous period · ${periodLabel(comparison.previous)}", value = DurationText.summary(comparison.previousSeconds))
                            comparison.percentage?.let { GroupedRow(label = "Change", value = "%+.1f%%".format(it)) }
                            Text(
                                if (interval.end > now) "Compared with the same calendar days in the previous period, including the full matching day." else "Compared with the full previous period.",
                                style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp, lineHeight = 18.sp),
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        if (projectID == null && summary.projects.isNotEmpty()) {
                            Section("Projects") { summary.projects.forEach { GroupedRow(label = it.name, value = DurationText.summary(it.seconds)) } }
                        }
                        if (summary.days.any { it.targetMinutes == null }) Hint("Older dates may not have a recorded goal.")
                    }
                }
            }
        }
        if (consistency) Dialog(onDismissRequest = { consistency = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Page(
                    modifier = Modifier.safeDrawingPadding(),
                    header = { ScreenHeader("Consistency", largeTitle = true, leading = { TextButton({ consistency = false }) { Icon(Icons.Outlined.ChevronLeft, null); Text("Stats") } }) }
                ) {
                    val current = Statistics.consistency(state, now, now)
                    Section("This week · All projects") {
                        Text("${current.focusedDays} of ${current.targetDays} focused days", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .5f))
                        val days = Statistics.dailySummaries(state, current.week, now = now)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceAround) {
                            days.forEach { day ->
                                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text(if (day.focusSeconds >= 600) "●" else "○", color = if (day.focusSeconds >= 600) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 24.sp)
                                    Text(Time.date(day.date).dayOfWeek.getDisplayName(TextStyle.NARROW, Locale.getDefault()), color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                    Hint("A focused day has at least 10 minutes of saved focus. Active sessions count after saving. Change your weekly target in Settings → Consistency.")
                    Section("Previous weeks") {
                        (1..8).forEach { offset ->
                            val date = Time.date(current.week.start).minusWeeks(offset.toLong())
                            val week = Statistics.consistency(state, Time.start(date, zone), now)
                            GroupedRow(label = date.format(DateTimeFormatter.ofPattern("d MMM yyyy")), value = "${week.focusedDays} days")
                            if (offset < 8) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .5f))
                        }
                    }
                }
            }
        }
        val historyInterval = drillDay?.let { Statistics.today(it) }
        val allSessions = if (historyInterval == null) sessions else sessions.filter { Statistics.overlap(it.startedAt, it.endedAt, historyInterval) > 0 || it.startedAt >= historyInterval.start && it.startedAt < historyInterval.end }
        val visibleSessions = if (fullHistory) allSessions else allSessions.take(5)
        GroupedSection(if (drillDay == null) "Recent sessions" else "Sessions · ${Time.date(drillDay!!)}") {
            if (drillDay != null) TextButton(onClick = { drillDay = null; fullHistory = false }) { Text("Show whole period") }
            if (visibleSessions.isEmpty()) Column(Modifier.fillMaxWidth().padding(vertical = 28.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Icon(Icons.Outlined.History, contentDescription = null, modifier = Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Text("No saved sessions", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            }
            if (!fullHistory && allSessions.size > 5) TextButton(onClick = { fullHistory = true }) { Text("View all sessions") }
            SessionHistory(visibleSessions.groupBy { Time.date(it.startedAt) }, state, historyInterval, openSession)
        }
    }
    if (picker) StatsPeriodPicker(range, interval?.start ?: now, state.sessions.minOfOrNull { it.startedAt }, now, { picker = false }) { date -> anchor = selection.select(date, now).anchor; drillDay = null; fullHistory = false; picker = false }
}

@Composable private fun StatsProjectFilter(projectID: String?, state: AppSnapshot, select: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val label = projectID?.let { id -> state.projects.find { it.id == id }?.name } ?: "All projects"
    Box {
        IconButton(onClick = { expanded = true }, modifier = Modifier.size(48.dp)) {
            Icon(Icons.Outlined.FilterList, contentDescription = "Filter projects: $label", modifier = Modifier.size(24.dp))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("All projects") }, onClick = { expanded = false; select(null) })
            state.projects.forEach { project -> DropdownMenuItem(text = { Text(project.name) }, onClick = { expanded = false; select(project.id) }) }
        }
    }
}

private fun periodTitle(selection: StatsDateSelection, interval: DateInterval, range: StatsDateRange, now: Double): String {
    val start = Time.date(interval.start)
    val end = Time.date(interval.end - 1)
    val date = DateTimeFormatter.ofPattern("d MMM yyyy")
    return when (range) {
        StatsDateRange.day -> "${if (selection.isCurrent(now)) "Today · " else ""}${start.format(DateTimeFormatter.ofPattern("EEE, d MMM yyyy"))}"
        StatsDateRange.week -> "${start.format(date)} – ${end.format(date)}"
        StatsDateRange.month -> start.format(DateTimeFormatter.ofPattern("MMMM yyyy"))
        StatsDateRange.all -> "All time"
    }
}

@Composable private fun FocusChart(days: List<DailySummary>, onSelect: (DailySummary) -> Unit) {
    val maximumMinutes = days.maxOfOrNull { it.focusSeconds / 60 } ?: 0.0
    val step = when { maximumMinutes <= 60 -> 20.0; maximumMinutes <= 150 -> 50.0; else -> kotlin.math.ceil(maximumMinutes / 180) * 60 }
    val maximum = (kotlin.math.ceil(maximumMinutes / step).coerceAtLeast(3.0) * step)
    val grid = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .7f)
    Column(Modifier.fillMaxWidth().padding(top = 16.dp, bottom = 12.dp)) {
        Row(Modifier.fillMaxWidth().height(160.dp)) {
            Box(Modifier.weight(1f).fillMaxHeight()) {
                Canvas(Modifier.fillMaxSize()) {
                    repeat(4) { index ->
                        val y = size.height * index / 3
                        drawLine(grid, Offset(0f, y), Offset(size.width, y), strokeWidth = 1.dp.toPx())
                    }
                    repeat(4) { index ->
                        val x = size.width * index / 3
                        drawLine(grid, Offset(x, 0f), Offset(x, size.height), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx())))
                    }
                }
                Row(Modifier.fillMaxSize().semantics { contentDescription = "Daily focus chart. Tap a day to view its sessions." }, horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.Bottom) {
                    days.forEach { day ->
                        Box(Modifier.weight(1f).fillMaxHeight().clickable(enabled = !day.isFuture, onClick = { onSelect(day) }).semantics {
                            contentDescription = "${Time.date(day.date)}: ${DurationText.summary(day.focusSeconds)}"; role = Role.Button
                        }, contentAlignment = Alignment.BottomCenter) {
                            if (day.focusSeconds > 0) Box(Modifier.fillMaxWidth(.75f).fillMaxHeight((day.focusSeconds / 60 / maximum).toFloat().coerceIn(0f, 1f)).clip(RoundedCornerShape(topStart = 2.dp, topEnd = 2.dp)).background(MaterialTheme.colorScheme.tertiary))
                        }
                    }
                }
            }
            Column(Modifier.width(32.dp).fillMaxHeight(), verticalArrangement = Arrangement.SpaceBetween, horizontalAlignment = Alignment.End) {
                (3 downTo 0).forEach { Text((maximum * it / 3).toInt().toString(), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
        }
        Row(Modifier.fillMaxWidth().padding(end = 32.dp, top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            days.filterIndexed { index, _ -> index == 0 || index == days.lastIndex || index == days.size / 3 || index == days.size * 2 / 3 }.forEach { day ->
                Text(Time.date(day.date).format(DateTimeFormatter.ofPattern("d MMM")), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

internal fun periodLabel(interval: DateInterval): String {
    val start = Time.date(interval.start)
    val end = Time.date(interval.end - 1)
    return if (start == end) start.toString() else "$start – $end"
}

@Composable private fun SessionHistory(groups: Map<java.time.LocalDate, List<FocusSession>>, state: AppSnapshot, day: DateInterval?, openSession: (String) -> Unit) {
    val orderedGroups = groups.entries.sortedByDescending { it.key }
    orderedGroups.forEachIndexed { groupIndex, (date, sessions) ->
        Text(
            date.format(DateTimeFormatter.ofPattern("EEE d MMM yyyy")),
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp, lineHeight = 16.sp),
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        val orderedSessions = sessions.sortedByDescending { it.startedAt }
        orderedSessions.forEachIndexed { index, session ->
            SessionListRow(session, state.projects.find { it.id == session.projectID }?.name ?: "Project", day) { openSession(session.id) }
            if (index < orderedSessions.lastIndex || groupIndex < orderedGroups.lastIndex) HorizontalDivider(Modifier.padding(horizontal = 16.dp))
        }
    }
}

@Composable internal fun SessionListRow(session: FocusSession, project: String, day: DateInterval?, open: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clickable(onClick = open, role = androidx.compose.ui.semantics.Role.Button).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
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
            Page(
                modifier = Modifier.safeDrawingPadding(),
                header = { ScreenHeader("Session", leading = { TextButton(dismiss) { Text("Done") } }) }
            ) {
                if (session == null) Hint("This session has been removed.") else {
                    Text(state.projects.find { it.id == session.projectID }?.name ?: "Project", style = MaterialTheme.typography.headlineSmall)
                    Section("Session") {
                        GroupedRow(label = "Focus time", value = DurationText.summary(session.duration))
                        GroupedRow(label = "Date", value = Time.date(session.startedAt).toString())
                        GroupedRow(label = "Outcome", value = session.outcome.name.replaceFirstChar { it.uppercase() })
                        GroupedRow(label = "Planned", value = DurationText.summary(session.plannedSeconds.toDouble()))
                    }
                    Section("Session plan") {
                        session.intention?.let { Text(it) } ?: Hint("No session plan")
                        GroupedRow(
                            label = if (session.intention == null) "Add session plan" else "Edit session plan",
                            onClick = { edit(NoteRequest("Session plan", session.intention.orEmpty()) { AppCommand.EditIntention(id, false, it) }) }
                        )
                    }
                    Section("Next step") {
                        session.nextStep?.let { Text(it) } ?: Hint("No next step")
                        GroupedRow(
                            label = if (session.nextStep == null) "Add next step" else "Edit next step",
                            onClick = { edit(NoteRequest("Next step", session.nextStep.orEmpty()) { AppCommand.SaveNextStep(id, it, false) }) }
                        )
                        if (session.nextStep != null) GroupedRow(
                            label = "Use for next session",
                            onClick = {
                                val existing = state.projects.find { it.id == session.projectID }?.breadcrumb?.text
                                if (existing != null && existing != session.nextStep) promote = true
                                else scope.launch {
                                    when (val result = execute(AppCommand.SetPendingPlan(session.projectID, session.nextStep.orEmpty()))) {
                                        is MutationResult.Failure -> error = result.message
                                        else -> Unit
                                    }
                                }
                            }
                        )
                    }
                    TextButton(onClick = { deleting = true }) { Text("Delete session", color = MaterialTheme.colorScheme.error) }
                    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                }
            }
        }
    }
    if (deleting) Confirm("Delete session?", "The saved focus time will be removed from your statistics. Thoughts remain saved.", "Delete", { deleting = false }) {
        scope.launch {
            when (val result = execute(AppCommand.DeleteSessions(setOf(id)))) {
                MutationResult.Success -> dismiss()
                is MutationResult.Failure -> error = result.message
            }
            deleting = false
        }
    }
    if (promote && session != null) Confirm("Replace next-session plan?", "This next step becomes the project's plan for its next focus session.", "Replace plan", { promote = false }) {
        scope.launch {
            when (val result = execute(AppCommand.SetPendingPlan(session.projectID, session.nextStep.orEmpty()))) {
                is MutationResult.Failure -> error = result.message
                else -> Unit
            }
            promote = false
        }
    }
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
            Page(
                modifier = Modifier.safeDrawingPadding(),
                header = { ScreenHeader("Choose a ${range.title.lowercase()}", leading = { TextButton(dismiss) { Text("Done") } }) }
            ) {
                SelectMenu("Year", StatsPeriodOptions.years(range, selected, earliest, now).reversed().map { it.toString() to it.toString() }, year.toString()) { year = it.toInt() }
                if (range == StatsDateRange.week) {
                    Section("Weeks") {
                        StatsPeriodOptions.weeks(year, now).reversed().forEach { week ->
                            GroupedRow(label = periodLabel(week), onClick = { choose(week.start) })
                        }
                    }
                } else {
                    Section("Months") {
                        StatsPeriodOptions.months(year, now).chunked(3).forEach { row ->
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                row.forEach { month ->
                                    OutlinedButton({ choose(month) }, Modifier.weight(1f).heightIn(min = 56.dp)) {
                                        Text(Time.date(month).month.getDisplayName(TextStyle.SHORT, Locale.getDefault()))
                                    }
                                }
                                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                            }
                        }
                    }
                }
            }
        }
    }
}
