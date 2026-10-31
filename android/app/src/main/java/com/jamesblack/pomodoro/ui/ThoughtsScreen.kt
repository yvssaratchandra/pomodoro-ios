package com.jamesblack.pomodoro.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.draw.clip
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
import kotlinx.coroutines.launch

internal const val unassignedThoughts = "__unassigned__"

internal fun filteredThoughts(state: AppSnapshot, projectID: String?, filter: String, query: String): List<CapturedThought> = state.thoughts.filter { (projectID == null || if (projectID == unassignedThoughts) it.projectID == null else it.projectID == projectID) && (filter == "All" || (it.completedAt != null) == (filter == "Done")) && (query.isBlank() || it.text.contains(query.trim(), ignoreCase = true)) }.sortedWith(compareByDescending<CapturedThought> { it.createdAt }.thenBy { it.id })

@Composable internal fun ThoughtsScreen(state: AppSnapshot, projectID: String?, selectProject: (String?) -> Unit, run: (AppCommand) -> Unit, capture: (ThoughtCaptureContext) -> Unit, edit: (CapturedThought) -> Unit) {
    var filter by rememberSaveable { mutableStateOf("Open") }
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
    }.joinToString(" · ")
    val emptyMessage = when {
        caughtUp -> "All caught up."
        query.isNotBlank() || projectID != null -> "No matching thoughts."
        filter == "Done" -> "No completed thoughts."
        else -> "No thoughts yet."
    }
    Page(horizontalPadding = 16.dp, verticalSpacing = 16.dp, header = {
        ScreenHeader(
            "Thoughts",
            largeTitle = true,
            leading = { ThoughtProjectFilter(projectID, state, selectProject) },
            trailing = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box {
                        IconButton(onClick = { actionsExpanded = true }, modifier = Modifier.size(48.dp)) {
                            Icon(Icons.Outlined.MoreHoriz, if (selecting) "Selection actions" else "Thought actions", modifier = Modifier.size(24.dp).border(1.5.dp, MaterialTheme.colorScheme.primary, CircleShape).padding(2.dp))
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
                        Icon(Icons.Outlined.Add, "Add a thought", modifier = Modifier.size(26.dp))
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
        Surface(shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
            BasicTextField(
                value = query, onValueChange = { query = it }, singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 7.dp).semantics { contentDescription = "Search thoughts" },
                decorationBox = { field -> Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Outlined.Search, null, Modifier.size(22.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(6.dp))
                    Box { if (query.isEmpty()) Text("Search thoughts", color = MaterialTheme.colorScheme.onSurfaceVariant); field() }
                } }
            )
        }
        Surface(shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
            Box(Modifier.padding(horizontal = 16.dp)) {
                SegmentedSelector(
                    options = listOf("Open" to "Open", "All" to "All", "Done" to "Done"),
                    selected = filter, onSelect = { filter = it }
                )
            }
        }
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
        Spacer(Modifier.height(4.dp))
        if (visible.isEmpty()) {
            Section("") {
                Hint(emptyMessage)
                if (caughtUp) TextButton(onClick = { filter = "Done" }) { Text("View completed") }
                else if (state.thoughts.isEmpty() && query.isBlank()) TextButton(onClick = { capture(ThoughtCaptureContext(projectID?.takeUnless { it == unassignedThoughts })) }) { Text("Add your first thought") }
            }
        } else {
            GroupedSection("") {
                visible.forEachIndexed { index, thought ->
                    ThoughtRow(
                        thought = thought,
                        project = if (projectID == null) thoughtProjectName(thought, state) else null,
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
                    if (index < visible.lastIndex) HorizontalDivider(Modifier.padding(start = 68.dp), color = MaterialTheme.colorScheme.outlineVariant)
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
        IconButton(onClick = { expanded = true }, modifier = Modifier.size(48.dp)) {
            Icon(Icons.Outlined.FilterList, label, Modifier.size(24.dp).border(1.5.dp, MaterialTheme.colorScheme.primary, CircleShape).padding(2.dp))
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

@OptIn(ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable private fun ThoughtRow(thought: CapturedThought, project: String?, selecting: Boolean = false, selected: Boolean = false, check: () -> Unit, edit: () -> Unit, delete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val toggled = if (selecting) selected else thought.completedAt != null
    val swipe = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) delete()
        false
    })
    SwipeToDismissBox(
        state = swipe, enableDismissFromStartToEnd = false, enableDismissFromEndToStart = !selecting,
        backgroundContent = { Box(Modifier.clearAndSetSemantics {}.fillMaxSize().background(if (swipe.dismissDirection == SwipeToDismissBoxValue.Settled) androidx.compose.ui.graphics.Color.Transparent else MaterialTheme.colorScheme.error).padding(end = 16.dp), contentAlignment = Alignment.CenterEnd) { Text("Delete", color = MaterialTheme.colorScheme.onError) } }
    ) {
        Row(
            Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer)
                .combinedClickable(onClick = edit, onLongClick = { if (!selecting) menu = true })
                .semantics { customActions = listOf(CustomAccessibilityAction("Edit thought") { edit(); true }, CustomAccessibilityAction("Delete thought") { delete(); true }) }
                .padding(start = 16.dp, end = 16.dp, top = 11.dp, bottom = 11.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            IconToggleButton(checked = toggled, onCheckedChange = { check() }, modifier = Modifier.size(44.dp).semantics {
                contentDescription = if (selecting) "Select thought" else if (toggled) "Mark thought open" else "Mark thought done"
                stateDescription = if (selecting) { if (toggled) "Selected" else "Not selected" } else if (toggled) "Done" else "Open"
            }) {
                Icon(if (selecting) { if (toggled) Icons.Outlined.CheckCircle else Icons.Outlined.RadioButtonUnchecked } else { if (toggled) Icons.Outlined.CheckBox else Icons.Outlined.CheckBoxOutlineBlank }, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
            }
            Column(Modifier.weight(1f).padding(start = 8.dp).heightIn(min = 44.dp), verticalArrangement = Arrangement.Center) {
                Text(thought.text, textDecoration = if (thought.completedAt != null) TextDecoration.LineThrough else null)
                if (project != null) Text(project, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text("Edit") }, onClick = { menu = false; edit() })
                DropdownMenuItem(text = { Text("Delete") }, onClick = { menu = false; delete() })
            }
        }
    }
}

private fun thoughtProjectName(thought: CapturedThought, state: AppSnapshot): String {
    val id = thought.projectID ?: return "Unassigned"
    return state.projects.find { it.id == id }?.name ?: "Project removed"
}

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
                Box(Modifier.padding(horizontal = 4.dp)) {
                    ScreenHeader(
                        title = if (context.originSessionID == null) "Capture thought" else "Session thoughts",
                        largeTitle = true,
                        trailing = { TextButton(onClick = close) { Text("Done") } }
                    )
                }
                error?.let {
                    Text(
                        it,
                        Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Column(
                    Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
                ) {
                    if (context.originSessionID == null) {
                        ThoughtComposerProject(projectID, state) { projectID = it }
                    }
                    GroupedSection("") {
                        if (saved.isEmpty()) Box(Modifier.padding(16.dp)) { Hint("Capture a thought and return to your focus. Saved thoughts remain even if you discard the session.") }
                        saved.forEachIndexed { index, thought ->
                            ThoughtRow(
                                thought,
                                null,
                                check = { run(AppCommand.SetThoughtsCompleted(setOf(thought.id), thought.completedAt == null)) },
                                edit = { editingID = thought.id },
                                delete = { deleting = thought }
                            )
                            if (index < saved.lastIndex) HorizontalDivider(Modifier.padding(start = 64.dp))
                        }
                    }
                }
                ComposerInput(
                    value = text, onValueChange = { if (!busy) text = it }, placeholder = "Add a thought…",
                    actionLabel = "Add thought", enabled = !busy && text.isNotBlank() && SessionText.count(text) <= 500,
                    onSend = {
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
                )
                    if (SessionText.count(text) >= 450) Text("${SessionText.count(text)} / 500", color = if (SessionText.count(text) > 500) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
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

@Composable internal fun ComposerInput(value: String, onValueChange: (String) -> Unit, placeholder: String, actionLabel: String, enabled: Boolean, onSend: () -> Unit) {
    val requester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(Unit) { requester.requestFocus(); keyboard?.show() }
    Surface(color = MaterialTheme.colorScheme.surfaceContainer) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Surface(Modifier.weight(1f), shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.onSurface.copy(alpha = .12f)) {
                BasicTextField(value, onValueChange, modifier = Modifier.focusRequester(requester).padding(horizontal = 12.dp, vertical = 10.dp).semantics { contentDescription = placeholder },
                    maxLines = 4, textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface), cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    decorationBox = { field -> Box { if (value.isEmpty()) Text(placeholder, color = MaterialTheme.colorScheme.onSurfaceVariant); field() } })
            }
            Spacer(Modifier.width(8.dp))
            IconButton(onClick = onSend, enabled = enabled, modifier = Modifier.size(44.dp)) {
                Icon(Icons.Outlined.ArrowCircleUp, actionLabel, Modifier.size(32.dp), tint = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
