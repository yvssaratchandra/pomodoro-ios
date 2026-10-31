package com.jamesblack.pomodoro.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.semantics.*
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.launch

internal const val unassignedThoughts = "__unassigned__"

internal fun filteredThoughts(state: AppSnapshot, projectID: String?, filter: String, query: String): List<CapturedThought> = state.thoughts.filter { (projectID == null || if (projectID == unassignedThoughts) it.projectID == null else it.projectID == projectID) && (filter == "All" || (it.completedAt != null) == (filter == "Done")) && (query.isBlank() || it.text.contains(query.trim(), ignoreCase = true)) }.sortedWith(compareByDescending<CapturedThought> { it.createdAt }.thenBy { it.id })

@Composable internal fun ThoughtsScreen(state: AppSnapshot, projectID: String?, selectProject: (String?) -> Unit, run: (AppCommand) -> Unit, capture: (ThoughtCaptureContext) -> Unit, edit: (CapturedThought) -> Unit) {
    var filter by rememberSaveable { mutableStateOf("All") }
    var query by rememberSaveable { mutableStateOf("") }
    var selecting by rememberSaveable { mutableStateOf(false) }
    var selected by remember { mutableStateOf(emptySet<String>()) }
    var actionsExpanded by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf<Set<String>?>(null) }
    BackHandler(selecting && deleting == null) { selecting = false; selected = emptySet() }
    LaunchedEffect(state.projects, projectID) { if (projectID != null && projectID != unassignedThoughts && state.projects.none { it.id == projectID }) selectProject(null) }
    val visible = remember(state.thoughts, projectID, filter, query) { filteredThoughts(state, projectID, filter, query) }
    LaunchedEffect(state.thoughts) { selected = selected.intersect(state.thoughts.map { it.id }.toSet()) }
    val projectThoughts = state.thoughts.filter { projectID == null || if (projectID == unassignedThoughts) it.projectID == null else it.projectID == projectID }
    val caughtUp = filter == "Open" && query.isBlank() && projectThoughts.any { it.completedAt != null }
    val activeFilterSummary = buildList {
        if (projectID != null) add(if (projectID == unassignedThoughts) "Unassigned" else state.projects.find { it.id == projectID }?.name ?: "Project")
        if (query.isNotBlank()) add("Search: $query")
        if (filter != "All") add(filter)
    }.joinToString(" · ")
    val emptyMessage = when {
        caughtUp -> "All caught up."
        query.isNotBlank() || projectID != null -> "No matching thoughts."
        filter == "Done" -> "No completed thoughts."
        else -> "No thoughts yet."
    }
    Page(header = {
        ScreenHeader(
            "Thoughts",
            largeTitle = true,
            leading = { ThoughtProjectFilter(projectID, state, selectProject) },
            trailing = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box {
                        IconButton(onClick = { actionsExpanded = true }, modifier = Modifier.size(48.dp)) {
                            Icon(Icons.Outlined.MoreHoriz, if (selecting) "Selection actions" else "Thought actions", modifier = Modifier.size(18.dp))
                        }
                        DropdownMenu(expanded = actionsExpanded, onDismissRequest = { actionsExpanded = false }) {
                            if (!selecting) {
                                DropdownMenuItem(
                                    text = { Text("Select thoughts") },
                                    enabled = visible.isNotEmpty(),
                                    onClick = { actionsExpanded = false; selecting = true; selected = emptySet() }
                                )
                            } else {
                                DropdownMenuItem(
                                    text = { Text("Select all visible") },
                                    enabled = visible.isNotEmpty(),
                                    onClick = { actionsExpanded = false; selected = visible.map { it.id }.toSet() }
                                )
                                DropdownMenuItem(
                                    text = { Text("Mark done") },
                                    enabled = selected.isNotEmpty(),
                                    onClick = { actionsExpanded = false; run(AppCommand.SetThoughtsCompleted(selected, true)) }
                                )
                                DropdownMenuItem(
                                    text = { Text("Mark open") },
                                    enabled = selected.isNotEmpty(),
                                    onClick = { actionsExpanded = false; run(AppCommand.SetThoughtsCompleted(selected, false)) }
                                )
                                DropdownMenuItem(
                                    text = { Text("Delete selected") },
                                    enabled = selected.isNotEmpty(),
                                    onClick = { actionsExpanded = false; deleting = selected }
                                )
                                DropdownMenuItem(
                                    text = { Text("Done selecting") },
                                    onClick = { actionsExpanded = false; selecting = false; selected = emptySet() }
                                )
                            }
                        }
                    }
                    IconButton(onClick = { capture(ThoughtCaptureContext(projectID?.takeUnless { it == unassignedThoughts })) }, modifier = Modifier.size(48.dp)) {
                        Icon(Icons.Outlined.Add, "Add a thought", modifier = Modifier.size(18.dp))
                    }
                }
            }
        )
    }) {
        if (selecting) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${selected.size} selected",
                    Modifier.weight(1f),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp)
                )
                TextButton(onClick = { selecting = false; selected = emptySet() }) { Text("Done") }
            }
        }
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            placeholder = { Text("Search thoughts") },
            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) }
        )
        SegmentedSelector(
            options = listOf("All" to "All", "Open" to "Open", "Done" to "Done"),
            selected = filter,
            onSelect = { filter = it }
        )
        if (activeFilterSummary.isNotEmpty()) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    activeFilterSummary,
                    Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp)
                )
                TextButton(onClick = { selectProject(null); query = ""; filter = "All"; selecting = false; selected = emptySet() }) { Text("Reset") }
            }
        }
        if (visible.isEmpty()) {
            Section("Thoughts") {
                Hint(emptyMessage)
                if (caughtUp) TextButton(onClick = { filter = "Done" }) { Text("View completed") }
                else if (state.thoughts.isEmpty() && query.isBlank()) TextButton(onClick = { capture(ThoughtCaptureContext(projectID?.takeUnless { it == unassignedThoughts })) }) { Text("Add your first thought") }
            }
        } else {
            GroupedSection("Thoughts") {
                visible.forEachIndexed { index, thought ->
                    ThoughtRow(
                        thought = thought,
                        project = thoughtProjectName(thought, state),
                        selecting = selecting,
                        selected = thought.id in selected,
                        check = {
                            if (selecting) selected = if (thought.id in selected) selected - thought.id else selected + thought.id
                            else run(AppCommand.SetThoughtsCompleted(setOf(thought.id), thought.completedAt == null))
                        },
                        edit = {
                            if (selecting) selected = if (thought.id in selected) selected - thought.id else selected + thought.id
                            else edit(thought)
                        },
                        delete = { deleting = setOf(thought.id) }
                    )
                    if (index < visible.lastIndex) HorizontalDivider(Modifier.padding(start = 64.dp, end = 16.dp))
                }
            }
        }
    }
    deleting?.let { ids ->
        Confirm(
            title = if (ids.size == 1) "Delete thought?" else "Delete ${ids.size} thoughts?",
            message = "These thoughts will be removed. You can Undo briefly after deleting.",
            action = "Delete",
            onDismiss = { deleting = null },
            onConfirm = { run(AppCommand.DeleteThoughts(ids)); deleting = null }
        )
    }
}

@Composable private fun ThoughtProjectFilter(projectID: String?, state: AppSnapshot, selectProject: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val label = when (projectID) {
        null -> "All projects"
        unassignedThoughts -> "Unassigned"
        else -> state.projects.find { it.id == projectID }?.name ?: "All projects"
    }
    Box {
        TextButton(onClick = { expanded = true }, modifier = Modifier.heightIn(min = 48.dp).widthIn(max = 148.dp), contentPadding = PaddingValues(horizontal = 0.dp)) {
            Icon(Icons.Outlined.FilterList, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(4.dp))
            Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp))
            Icon(Icons.Outlined.ExpandMore, contentDescription = null, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("All projects") }, onClick = { expanded = false; selectProject(null) })
            DropdownMenuItem(text = { Text("Unassigned") }, onClick = { expanded = false; selectProject(unassignedThoughts) })
            state.projects.forEach { project ->
                DropdownMenuItem(text = { Text(project.name) }, onClick = { expanded = false; selectProject(project.id) })
            }
        }
    }
}

@Composable private fun ThoughtRow(thought: CapturedThought, project: String?, selecting: Boolean = false, selected: Boolean = false, check: () -> Unit, edit: () -> Unit, delete: () -> Unit) {
    val toggled = if (selecting) selected else thought.completedAt != null
    Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconToggleButton(
            checked = toggled,
            onCheckedChange = { check() },
            modifier = Modifier.size(48.dp).semantics {
                contentDescription = if (selecting) "Select thought" else if (thought.completedAt != null) "Mark thought open" else "Mark thought done"
                stateDescription = if (selecting) { if (selected) "Selected" else "Not selected" } else { if (thought.completedAt != null) "Done" else "Open" }
            }
        ) {
            Icon(
                imageVector = if (toggled) Icons.Outlined.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
                contentDescription = null,
                tint = if (toggled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Column(
            Modifier.weight(1f).clickable(onClick = edit).padding(horizontal = 8.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(3.dp)
        ) {
            Text(thought.text, textDecoration = if (thought.completedAt != null) TextDecoration.LineThrough else null)
            Text(
                listOfNotNull(project, thoughtDate(thought.createdAt)).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp, lineHeight = 16.sp),
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        if (!selecting) IconButton(onClick = delete, modifier = Modifier.size(48.dp)) {
            Icon(Icons.Outlined.Delete, "Delete thought", tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

private fun thoughtProjectName(thought: CapturedThought, state: AppSnapshot): String {
    val id = thought.projectID ?: return "Unassigned"
    return state.projects.find { it.id == id }?.name ?: "Project removed"
}

private fun thoughtDate(seconds: Double): String =
    Time.toInstant(seconds).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("d MMM · HH:mm"))

@Composable internal fun ThoughtComposer(state: AppSnapshot, context: ThoughtCaptureContext, dismiss: () -> Unit, execute: suspend (AppCommand) -> MutationResult) {
    var text by rememberSaveable(context.id) { mutableStateOf("") }
    var projectID by rememberSaveable(context.id) { mutableStateOf(context.projectID) }
    val initialIDs = rememberSaveable(context.id) { ArrayList(state.thoughts.map { it.id }) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var confirming by remember { mutableStateOf(false) }
    var editingID by rememberSaveable { mutableStateOf<String?>(null) }
    val editing = state.thoughts.find { it.id == editingID }
    var deleting by remember { mutableStateOf<CapturedThought?>(null) }
    val scope = rememberCoroutineScope()
    val close = { if (!busy) { if (text.isNotBlank()) confirming = true else dismiss() } }
    val saved = state.thoughts.filter { if (context.originSessionID != null) it.originSessionID == context.originSessionID else it.id !in initialIDs }.sortedBy { it.createdAt }
    val run: (AppCommand) -> Unit = { command -> scope.launch { when (val result = execute(command)) { is MutationResult.Failure -> error = result.message; else -> {} } } }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding()) {
                ScreenHeader(
                    title = if (context.originSessionID == null) "Capture thought" else "Session thoughts",
                    leading = { TextButton(onClick = close) { Text("Done") } }
                )
                error?.let {
                    Text(
                        it,
                        Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Column(
                    Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    if (context.originSessionID == null) {
                        ThoughtComposerProject(projectID, state) { projectID = it }
                    } else {
                        Section("Capture context") {
                            GroupedRow(label = "Project", value = state.projects.find { it.id == context.projectID }?.name ?: "Project unavailable")
                            if (state.sessions.none { it.id == context.originSessionID } && state.activeTimer?.id != context.originSessionID) Hint("Session removed")
                            else Hint("This thought stays with the focus session where capture began.")
                        }
                    }
                    GroupedSection(if (context.originSessionID == null) "Saved thoughts" else "Session thoughts") {
                        if (saved.isEmpty()) Box(Modifier.padding(16.dp)) { Hint("Capture a thought and return to your focus. Saved thoughts remain even if you discard the session.") }
                        saved.forEachIndexed { index, thought ->
                            ThoughtRow(
                                thought,
                                thoughtProjectName(thought, state),
                                check = { run(AppCommand.SetThoughtsCompleted(setOf(thought.id), thought.completedAt == null)) },
                                edit = { editingID = thought.id },
                                delete = { deleting = thought }
                            )
                            if (index < saved.lastIndex) HorizontalDivider(Modifier.padding(start = 64.dp))
                        }
                    }
                    OutlinedTextField(
                        value = text,
                        onValueChange = { text = it },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Add a thought…") },
                        maxLines = 4,
                        enabled = !busy
                    )
                    if (SessionText.count(text) >= 450) Text("${SessionText.count(text)} / 500", color = if (SessionText.count(text) > 500) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                    Action("Add thought", !busy && text.isNotBlank() && SessionText.count(text) <= 500) {
                        scope.launch {
                            busy = true
                            val captured = if (context.originSessionID == null) context.copy(projectID = projectID) else context
                            when (val result = execute(AppCommand.CaptureThought(captured, text))) {
                                MutationResult.Success -> { text = ""; error = null }
                                is MutationResult.Failure -> error = result.message
                            }
                            busy = false
                        }
                    }
                }
            }
        }
    }
    if (confirming) AlertDialog(onDismissRequest = { confirming = false }, title = { Text("Discard this draft?") }, text = { Text("Thoughts you've already added remain saved.") }, dismissButton = { TextButton({ confirming = false }) { Text("Keep editing") } }, confirmButton = { TextButton(dismiss) { Text("Discard draft") } })
    editing?.let { thought -> key(thought.id) { TextEditor("Edit thought", thought.text, 500, { editingID = null }) { execute(AppCommand.EditThought(thought.id, it)) } } }
    deleting?.let { thought -> Confirm("Delete thought?", "You can Undo briefly after deleting.", "Delete", { deleting = null }) { run(AppCommand.DeleteThoughts(setOf(thought.id))); deleting = null } }
}

@Composable private fun ThoughtComposerProject(projectID: String?, state: AppSnapshot, onSelect: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val current = when (projectID) {
        null -> "Unassigned"
        else -> state.projects.find { it.id == projectID }?.name ?: "Project unavailable"
    }
    Box {
        GroupedRow(label = "Project", value = current, onClick = { expanded = true })
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text("Unassigned") }, onClick = { expanded = false; onSelect(null) })
            state.projects.forEach { project -> DropdownMenuItem(text = { Text(project.name) }, onClick = { expanded = false; onSelect(project.id) }) }
        }
    }
}
