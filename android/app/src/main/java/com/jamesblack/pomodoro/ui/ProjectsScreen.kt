package com.jamesblack.pomodoro.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.ChevronLeft
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.LocalDate

@Composable
internal fun ProjectsScreen(
    state: AppSnapshot,
    now: Double,
    run: (AppCommand) -> Unit,
    edit: (String) -> Unit,
    create: () -> Unit,
    focus: (String) -> Unit,
    thoughts: (String) -> Unit,
    session: (String) -> Unit,
    platform: PlatformActions,
    execute: suspend (AppCommand) -> MutationResult,
    onExit: () -> Unit = {},
    openPlan: (String) -> Unit = {}
) {
    var detailID by rememberSaveable { mutableStateOf<String?>(null) }
    var showOnHold by rememberSaveable { mutableStateOf(false) }
    var showCompleted by rememberSaveable { mutableStateOf(false) }
    var showAllSessions by rememberSaveable { mutableStateOf(false) }
    var menuExpanded by remember { mutableStateOf(false) }
    var mergeSource by rememberSaveable { mutableStateOf<String?>(null) }
    var mergeDestination by rememberSaveable { mutableStateOf<String?>(null) }
    var confirmMerge by rememberSaveable { mutableStateOf(false) }
    var deleteID by rememberSaveable { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val project = state.projects.firstOrNull { it.id == detailID }
    val canMerge = project != null && project.id != state.activeTimer?.projectID && state.projects.any {
        it.id != project.id && it.id != state.activeTimer?.projectID
    }
    val canDelete = project != null && project.breadcrumb == null &&
        state.sessions.none { it.projectID == project.id } &&
        state.thoughts.none { it.projectID == project.id } &&
        state.activeTimer?.projectID != project.id && state.breakOffer?.projectID != project.id

    BackHandler(enabled = detailID != null && mergeSource == null && deleteID == null) {
        detailID = null
        showAllSessions = false
        error = null
    }

    key(detailID ?: "projects") {
        Page(horizontalPadding = 16.dp, verticalSpacing = 32.dp, header = {
            ScreenHeader(
                title = project?.name ?: "Projects",
                largeTitle = false,
                leading = {
                    TextButton(modifier = Modifier.semantics { contentDescription = "Back" }, onClick = { if (project == null) onExit() else { detailID = null; error = null } }, contentPadding = PaddingValues(0.dp)) {
                        Icon(Icons.Outlined.ChevronLeft, contentDescription = null, modifier = Modifier.size(24.dp))
                        Text(if (project == null) "Focus" else "Projects")
                    }
                },
                trailing = {
                    if (project == null) {
                        IconButton(onClick = create) {
                            Icon(Icons.Outlined.Add, contentDescription = "Create project", modifier = Modifier.size(24.dp))
                        }
                    } else {
                        Box {
                            IconButton(onClick = { menuExpanded = true }) {
                                Icon(Icons.Outlined.MoreHoriz, contentDescription = "Project actions", modifier = Modifier.size(24.dp))
                            }
                            DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                                DropdownMenuItem(
                                    text = { Text("Project settings and goals") },
                                    onClick = { menuExpanded = false; edit(project.id) }
                                )
                                if (project.status == ProjectStatus.ongoing) {
                                    DropdownMenuItem(
                                        text = { Text("Create shortcut") },
                                        onClick = { menuExpanded = false; platform.pinShortcut(AppRoute.StartFocus(project.id)) }
                                    )
                                }
                                DropdownMenuItem(
                                    text = { Text("Merge into another project") },
                                    enabled = canMerge,
                                    onClick = {
                                        menuExpanded = false
                                        mergeSource = project.id
                                        mergeDestination = null
                                        confirmMerge = false
                                        error = null
                                    }
                                )
                                DropdownMenuItem(
                                    text = { Text("Delete empty project", color = MaterialTheme.colorScheme.error) },
                                    enabled = canDelete,
                                    onClick = { menuExpanded = false; deleteID = project.id; error = null }
                                )
                            }
                        }
                    }
                }
            )
        }) {
            if (project == null) {
                val ongoing = state.projects.filter { it.status == ProjectStatus.ongoing }.sortedBy { it.name.lowercase() }
                val onHold = state.projects.filter { it.status == ProjectStatus.suspended }.sortedBy { it.name.lowercase() }
                val completed = state.projects.filter { it.status == ProjectStatus.completed }.sortedBy { it.name.lowercase() }

                if (state.goalPlan.pendingLegacyDailySchedule != null) {
                    GroupedSection("Assign previous daily goal") {
                        Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                            Hint("Choose one project for this goal. It will not be applied to every project.")
                        }
                        state.projects.sortedBy { it.name.lowercase() }.forEach { candidate ->
                            InsetGroupedRow("Assign to ${candidate.name}", onClick = { run(AppCommand.AssignLegacyDailyGoal(candidate.id)) })
                        }
                        InsetGroupedRow("Discard previous goal", onClick = { run(AppCommand.DiscardLegacyDailyGoal) })
                    }
                }

                if (ongoing.isNotEmpty()) {
                    Column(Modifier.fillMaxWidth()) {
                        Text("ACTIVE", Modifier.padding(start = 16.dp, bottom = 8.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        ongoing.forEachIndexed { index, candidate ->
                            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Outlined.FolderOpen, contentDescription = null, modifier = Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
                                Spacer(Modifier.width(16.dp))
                                GroupedRow(candidate.name, onClick = { detailID = candidate.id; showAllSessions = false; error = null })
                            }
                            if (index < ongoing.lastIndex) HorizontalDivider(Modifier.padding(start = 56.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .55f))
                        }
                    }
                }
                if (onHold.isNotEmpty() || completed.isNotEmpty()) {
                    GroupedSection("Other projects") {
                        if (onHold.isNotEmpty()) {
                            InsetGroupedRow("On Hold (${onHold.size})", if (showOnHold) "Hide" else "Show", onClick = { showOnHold = !showOnHold })
                            if (showOnHold) onHold.forEach { candidate -> InsetGroupedRow(candidate.name, onClick = { detailID = candidate.id; showAllSessions = false; error = null }) }
                        }
                        if (completed.isNotEmpty()) {
                            InsetGroupedRow("Completed (${completed.size})", if (showCompleted) "Hide" else "Show", onClick = { showCompleted = !showCompleted })
                            if (showCompleted) completed.forEach { candidate -> InsetGroupedRow(candidate.name, onClick = { detailID = candidate.id; showAllSessions = false; error = null }) }
                        }
                    }
                }
                if (state.projects.isEmpty()) {
                    Section("No projects yet") {
                        Hint("Create a project to begin focused work.")
                        Action("Create Project", onClick = create)
                    }
                } else if (ongoing.isEmpty() && onHold.isEmpty() && completed.isEmpty()) {
                    Hint("No projects to show.")
                }
            } else {
                val projectSessions = state.sessions
                    .filter { it.projectID == project.id }
                    .sortedByDescending { it.startedAt }
                val shownSessions = if (showAllSessions) projectSessions else projectSessions.take(5)
                val week = GoalEngine.week(now)
                val weekSeconds = Statistics.total(state, project.id, week, now)
                val weeklyGoal = GoalEngine.weeklyTarget(project.id, now, state.goalPlan)
                val planCount = SessionPlanText.items(project.breadcrumb?.text).size

                GroupedSection("Summary") {
                    InsetGroupedRow("Total focus", DurationText.summary(Statistics.total(state, project.id)))
                    InsetGroupedRow(
                        "This week",
                        if (weeklyGoal == null) "${DurationText.summary(weekSeconds)} · No goal"
                        else "${DurationText.summary(weekSeconds)} of ${DurationText.summary(weeklyGoal * 60.0)}"
                    )
                    if (weeklyGoal != null) {
                        LinearProgressIndicator(
                            progress = { (weekSeconds / (weeklyGoal * 60.0)).toFloat().coerceIn(0f, 1f) },
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                            color = MaterialTheme.colorScheme.primary,
                            trackColor = MaterialTheme.colorScheme.surfaceVariant
                        )
                    }
                    InsetGroupedRow("Focus duration", "${project.preferredFocusMinutes} min")
                    if (project.status != ProjectStatus.ongoing) InsetGroupedRow("Status", project.status.title)
                }

                GroupedSection("Next focus") {
                    InsetGroupedRow(
                        label = if (planCount == 0) "Plan next session" else "Session plan · $planCount ${if (planCount == 1) "task" else "tasks"}",
                        value = "Edit",
                        onClick = { openPlan(project.id) }
                    )
                    InsetGroupedRow(
                        label = "Thoughts",
                        value = "${state.thoughts.count { it.projectID == project.id }}",
                        onClick = { thoughts(project.id) }
                    )
                }

                Section("Recent sessions") {
                    if (shownSessions.isEmpty()) Hint("No sessions yet.")
                    shownSessions.forEach { saved ->
                        SessionListRow(saved, project.name, null) { session(saved.id) }
                    }
                    if (projectSessions.size > 5) {
                        GroupedRow(
                            if (showAllSessions) "Show recent sessions" else "View all sessions",
                            onClick = { showAllSessions = !showAllSessions }
                        )
                    }
                }

                if (project.status == ProjectStatus.ongoing) Action("Use for Focus") { focus(project.id) }
            }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(horizontal = 16.dp)) }
        }
    }

    mergeSource?.let { sourceID ->
        val source = state.projects.firstOrNull { it.id == sourceID }
        val destinations = state.projects.filter { it.id != sourceID && it.id != state.activeTimer?.projectID }
        AlertDialog(
            onDismissRequest = { if (!busy) { mergeSource = null; confirmMerge = false; error = null } },
            title = { Text(if (confirmMerge) "Merge project?" else "Merge into another project") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (confirmMerge) {
                        Text("Sessions and thoughts from ${source?.name ?: "this project"} will move to ${destinations.firstOrNull { it.id == mergeDestination }?.name ?: "the selected project"}. The destination keeps its settings and goals. This cannot be undone.")
                    } else {
                        Hint("Sessions and thoughts move to the destination. Its existing goals are kept. Resolve conflicting session plans before merging.")
                        SelectMenu("Destination", destinations.map { it.id to it.name }, mergeDestination) { mergeDestination = it }
                    }
                    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                }
            },
            dismissButton = {
                TextButton(onClick = {
                    if (confirmMerge) confirmMerge = false
                    else { mergeSource = null; error = null }
                }, enabled = !busy) { Text(if (confirmMerge) "Back" else "Cancel") }
            },
            confirmButton = {
                TextButton(
                    enabled = !busy && mergeDestination != null && destinations.any { it.id == mergeDestination },
                    onClick = {
                        if (!confirmMerge) {
                            confirmMerge = true
                            error = null
                        } else {
                            scope.launch {
                                busy = true
                                when (val result = execute(AppCommand.MergeProjects(sourceID, mergeDestination!!))) {
                                    MutationResult.Success -> {
                                        detailID = mergeDestination
                                        mergeSource = null
                                        confirmMerge = false
                                        error = null
                                    }
                                    is MutationResult.Failure -> error = result.message
                                }
                                busy = false
                            }
                        }
                    }
                ) { Text(if (confirmMerge) "Merge and remove" else "Continue") }
            }
        )
    }

    deleteID?.let { id ->
        AlertDialog(
            onDismissRequest = { if (!busy) { deleteID = null; error = null } },
            title = { Text("Delete empty project?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Only a project without saved sessions, thoughts, a plan, or a running timer can be deleted.")
                    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                }
            },
            dismissButton = { TextButton(onClick = { deleteID = null; error = null }, enabled = !busy) { Text("Cancel") } },
            confirmButton = {
                TextButton(enabled = !busy, onClick = {
                    scope.launch {
                        busy = true
                        when (val result = execute(AppCommand.DeleteEmptyProject(id))) {
                            MutationResult.Success -> { deleteID = null; detailID = null; error = null }
                            is MutationResult.Failure -> error = result.message
                        }
                        busy = false
                    }
                }) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            }
        )
    }
}

@Composable
internal fun ProjectEditor(
    initial: ProjectDraft,
    state: AppSnapshot,
    now: Double,
    dismiss: () -> Unit,
    save: suspend (ProjectDraft) -> MutationResult
) {
    var name by rememberSaveable { mutableStateOf(initial.name) }
    var status by rememberSaveable { mutableStateOf(initial.status.name) }
    var focus by rememberSaveable { mutableIntStateOf(initial.focusMinutes) }
    var shortBreak by rememberSaveable { mutableIntStateOf(initial.shortBreakMinutes) }
    var longBreak by rememberSaveable { mutableIntStateOf(initial.longBreakMinutes) }
    var daily by rememberSaveable { mutableStateOf(initial.dailySchedule) }
    var weekly by rememberSaveable { mutableStateOf(initial.weeklyMinutes) }
    var scheduled by rememberSaveable(stateSaver = scheduledEditsSaver) { mutableStateOf(initial.scheduledWeeklyEdits) }
    var page by rememberSaveable { mutableStateOf("root") }
    var timerDisclosure by rememberSaveable { mutableStateOf(false) }
    var futureDate by rememberSaveable { mutableStateOf(Time.date(GoalEngine.week(now).end).toString()) }
    var futureGoal by rememberSaveable { mutableStateOf("") }
    var confirming by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val draft = initial.copy(
        name = name,
        status = ProjectStatus.valueOf(status),
        focusMinutes = focus,
        shortBreakMinutes = shortBreak,
        longBreakMinutes = longBreak,
        dailySchedule = daily,
        weeklyMinutes = weekly,
        scheduledWeeklyEdits = scheduled
    )
    val close = {
        if (!busy) {
            if (draft.hasChanges) confirming = true else dismiss()
        }
    }
    val popPage = {
        page = when (page) {
            "daily", "weekly" -> "goals"
            "timer", "goals" -> "root"
            else -> "root"
        }
    }
    val pageTitle = when (page) {
        "timer" -> "Timer settings"
        "goals" -> "Goals"
        "daily" -> "Daily goal"
        "weekly" -> "Weekly goal"
        else -> if (initial.isNew) "New project" else "Project settings"
    }
    BackHandler(enabled = true) {
        if (page != "root") popPage() else close()
    }

    Dialog(onDismissRequest = { if (page == "root") close() else popPage() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            key(page) {
                Page(
                    modifier = Modifier.safeDrawingPadding().imePadding(),
                    header = {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            ScreenHeader(
                                title = pageTitle,
                                largeTitle = false,
                                leading = {
                                    TextButton(onClick = { if (page == "root") close() else popPage() }, enabled = !busy) {
                                        Text(if (page == "root") "Cancel" else "Back")
                                    }
                                },
                                trailing = {
                                    TextButton(
                                        enabled = !busy && draft.hasChanges && name.isNotBlank() && SessionText.count(name) <= 100,
                                        onClick = {
                                            scope.launch {
                                                busy = true
                                                when (val result = save(draft)) {
                                                    MutationResult.Success -> dismiss()
                                                    is MutationResult.Failure -> error = result.message
                                                }
                                                busy = false
                                            }
                                        }
                                    ) { Text(if (busy) "Saving" else "Save") }
                                }
                            )
                            error?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(horizontal = 16.dp)) }
                        }
                    }
                ) {
                    when (page) {
                        "root" -> {
                            Section("Project") {
                                OutlinedTextField(
                                    value = name,
                                    onValueChange = { name = it },
                                    modifier = Modifier.fillMaxWidth(),
                                    label = { Text("Project name") },
                                    singleLine = true,
                                    supportingText = { Text("${SessionText.count(name)} / 100") },
                                    enabled = !busy
                                )
                                if (!initial.isNew) {
                                    val active = state.activeTimer?.projectID == initial.projectID
                                    ChoiceRow(
                                        label = "Status",
                                        selected = ProjectStatus.valueOf(status).title,
                                        options = ProjectStatus.entries.map { it.name to it.title },
                                        enabled = !active && !busy,
                                        onSelect = { status = it }
                                    )
                                    if (active) Hint("End this project's timer before changing its status.")
                                }
                            }
                            if (initial.isNew) {
                                Section("Optional") {
                                    GroupedRow(
                                        "Timer settings",
                                        value = if (timerDisclosure) "Hide" else "Show",
                                        onClick = { timerDisclosure = !timerDisclosure }
                                    )
                                    if (timerDisclosure) TimerDraftFields(
                                        focus = focus,
                                        shortBreak = shortBreak,
                                        longBreak = longBreak,
                                        enabled = !busy,
                                        onFocus = { focus = it },
                                        onShortBreak = { shortBreak = it },
                                        onLongBreak = { longBreak = it }
                                    )
                                }
                            } else {
                                Section("Project options") {
                                    GroupedRow("Timer settings", "${initial.baseline.project.preferredFocusMinutes} min focus", onClick = { page = "timer" })
                                    GroupedRow("Daily and weekly goals", "Edit", onClick = { page = "goals" })
                                }
                            }
                        }
                        "timer" -> Section("Durations") {
                            TimerDraftFields(
                                focus = focus,
                                shortBreak = shortBreak,
                                longBreak = longBreak,
                                enabled = !busy,
                                onFocus = { focus = it },
                                onShortBreak = { shortBreak = it },
                                onLongBreak = { longBreak = it }
                            )
                        }
                        "goals" -> Section("Goals") {
                            GroupedRow("Daily goal", dailySummary(daily), onClick = { page = "daily" })
                            GroupedRow("Weekly goal", weekly?.let { DurationText.summary(it * 60.0) } ?: "Off", onClick = { page = "weekly" })
                        }
                        "daily" -> Section("Daily goal") {
                            Hint("Changes take effect today. Earlier days keep their recorded goals.")
                            if (daily == null) {
                                Hint("No daily goal is set.")
                                Action("Set daily goals", enabled = !busy) { daily = List(7) { 60 } }
                            } else {
                                MinuteControl("Same every day", daily!!.first(), 0, 1440, onChange = { daily = List(7) { it } })
                                listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday").forEachIndexed { index, label ->
                                    MinuteControl(label, daily!![index], 0, 1440, onChange = { minutes ->
                                        daily = daily!!.mapIndexed { day, value -> if (day == index) minutes else value }
                                    })
                                }
                                Hint("0 minutes means a rest day.")
                            }
                        }
                        else -> {
                            Section("Weekly goal") {
                                Hint("Weekly goals are independent of daily goals and do not change timer durations.")
                                ToggleRow("Weekly goal", weekly != null, enabled = !busy) { weekly = if (it) (weekly ?: 300) else null }
                                weekly?.let { value -> MinuteControl("Minutes per week", value, 1, 10080, onChange = { weekly = it }) }
                            }
                            Section("Scheduled changes") {
                                Hint("Schedule a Monday after the current week. Leave minutes blank to turn the goal off.")
                                OutlinedTextField(
                                    value = futureDate,
                                    onValueChange = { futureDate = it },
                                    modifier = Modifier.fillMaxWidth(),
                                    label = { Text("Monday (YYYY-MM-DD)") },
                                    singleLine = true,
                                    enabled = !busy
                                )
                                OutlinedTextField(
                                    value = futureGoal,
                                    onValueChange = { futureGoal = it.filter(Char::isDigit).take(5) },
                                    modifier = Modifier.fillMaxWidth(),
                                    label = { Text("Weekly minutes, or blank for off") },
                                    singleLine = true,
                                    enabled = !busy
                                )
                                val date = runCatching { LocalDate.parse(futureDate) }.getOrNull()
                                val valid = date != null && date.dayOfWeek == DayOfWeek.MONDAY &&
                                    LocalDay(date) > initial.createdWeek &&
                                    (futureGoal.isBlank() || futureGoal.toIntOrNull()?.let { it in 1..10080 } == true)
                                Action("Add scheduled change", enabled = valid && !busy) {
                                    val next = date ?: return@Action
                                    scheduled = scheduled + (LocalDay(next) to ScheduledWeeklyEdit.Set(futureGoal.toIntOrNull()))
                                    futureGoal = ""
                                }
                                scheduledWeeklyRows(initial, scheduled).forEach { (day, minutes) ->
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        Text("${day.date()}: ${minutes?.let { "$it min" } ?: "Off"}", Modifier.weight(1f))
                                        TextButton(enabled = !busy, onClick = { scheduled = scheduled + (day to ScheduledWeeklyEdit.Cancel) }) { Text("Cancel change") }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text("Discard changes?") },
            text = { Text("Your project settings have not been saved.") },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text("Keep editing") } },
            confirmButton = { TextButton(onClick = dismiss) { Text("Discard") } }
        )
    }
}

@Composable
private fun TimerDraftFields(
    focus: Int,
    shortBreak: Int,
    longBreak: Int,
    enabled: Boolean,
    onFocus: (Int) -> Unit,
    onShortBreak: (Int) -> Unit,
    onLongBreak: (Int) -> Unit
) {
    MinuteControl(
        "Focus", focus, 10, 60,
        trigger = { open -> TextButton(open, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = enabled) { Text("Focus · $focus min") } },
        onChange = onFocus
    )
    MinuteControl(
        "Short break", shortBreak, 1, 60,
        trigger = { open -> TextButton(open, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = enabled) { Text("Short break · $shortBreak min") } },
        onChange = onShortBreak
    )
    MinuteControl(
        "Long break", longBreak, 1, 60,
        trigger = { open -> TextButton(open, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = enabled) { Text("Long break · $longBreak min") } },
        onChange = onLongBreak
    )
}


@Composable
private fun ToggleRow(label: String, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
    }
}

private fun dailySummary(schedule: List<Int>?): String {
    if (schedule == null) return "Off"
    if (schedule.all { it == schedule.first() }) return "${schedule.first()} min daily"
    if (schedule.take(5).all { it == schedule.first() } && schedule.takeLast(2).all { it == schedule[5] }) {
        return if (schedule[5] == 0) "${schedule.first()} min weekdays" else "Weekdays & weekends"
    }
    return "Custom schedule"
}

private fun scheduledWeeklyRows(
    initial: ProjectDraft,
    edits: Map<LocalDay, ScheduledWeeklyEdit>
): List<Pair<LocalDay, Int?>> {
    val current = initial.baseline.weeklyRevisions
        .filter { it.effectiveFrom > initial.createdWeek }
        .associate { it.effectiveFrom to it.minutes }
        .toMutableMap()
    edits.forEach { (day, edit) ->
        when (edit) {
            is ScheduledWeeklyEdit.Set -> current[day] = edit.minutes
            ScheduledWeeklyEdit.Cancel -> current.remove(day)
        }
    }
    return current.toSortedMap().toList()
}

internal val scheduledEditsSaver = listSaver<Map<LocalDay, ScheduledWeeklyEdit>, String>(
    save = { edits -> edits.map { (day, edit) -> "${day.date()}|${when (edit) {
        ScheduledWeeklyEdit.Cancel -> "cancel"
        is ScheduledWeeklyEdit.Set -> edit.minutes?.toString() ?: "off"
    }}" } },
    restore = { saved -> saved.associate { item ->
        val parts = item.split('|')
        LocalDay(LocalDate.parse(parts[0])) to when (parts[1]) {
            "cancel" -> ScheduledWeeklyEdit.Cancel
            "off" -> ScheduledWeeklyEdit.Set(null)
            else -> ScheduledWeeklyEdit.Set(parts[1].toInt())
        }
    } }
)
