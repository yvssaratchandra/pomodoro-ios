package com.jamesblack.pomodoro.ui

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import kotlinx.coroutines.launch

internal fun filteredThoughts(state: AppSnapshot, projectID: String?, filter: String, query: String): List<CapturedThought> = state.thoughts.filter { (projectID == null || it.projectID == projectID) && (filter == "All" || (it.completedAt != null) == (filter == "Done")) && (query.isBlank() || it.text.contains(query.trim(), ignoreCase = true)) }.sortedWith(compareByDescending<CapturedThought> { it.createdAt }.thenBy { it.id })

@Composable internal fun ThoughtsScreen(state: AppSnapshot, projectID: String?, selectProject: (String?) -> Unit, run: (AppCommand) -> Unit, capture: (ThoughtCaptureContext) -> Unit, edit: (CapturedThought) -> Unit) {
    var filter by rememberSaveable { mutableStateOf("All") }
    var query by rememberSaveable { mutableStateOf("") }
    var selecting by rememberSaveable { mutableStateOf(false) }
    var selected by remember { mutableStateOf(emptySet<String>()) }
    var deleting by remember { mutableStateOf(false) }
    val visible = remember(state.thoughts, projectID, filter, query) { filteredThoughts(state, projectID, filter, query) }
    LaunchedEffect(state.thoughts) { selected = selected.intersect(state.thoughts.map { it.id }.toSet()) }
    Page {
        Action("Add a thought") { capture(ThoughtCaptureContext(projectID)) }
        OutlinedTextField(query, { query = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text("Search thoughts") })
        SelectMenu("Project", listOf("" to "All projects") + state.projects.map { it.id to it.name }, projectID ?: "") { selectProject(it.takeIf(String::isNotEmpty)) }
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) { listOf("All", "Open", "Done").forEach { option -> FilterChip(selected = option == filter, onClick = { filter = option }, label = { Text(option) }) } }
        TextButton({ selecting = !selecting; selected = emptySet() }) { Text(if (selecting) "Done selecting" else "Select thoughts") }
        if (selecting) {
            Text("${selected.size} selected")
            Row(Modifier.horizontalScroll(rememberScrollState())) {
                TextButton({ selected = visible.map { it.id }.toSet() }) { Text("Select all visible") }
                TextButton(enabled = selected.isNotEmpty(), onClick = { run(AppCommand.SetThoughtsCompleted(selected, true)); selected = emptySet() }) { Text("Mark done") }
                TextButton(enabled = selected.isNotEmpty(), onClick = { run(AppCommand.SetThoughtsCompleted(selected, false)); selected = emptySet() }) { Text("Mark open") }
                TextButton(enabled = selected.isNotEmpty(), onClick = { deleting = true }) { Text("Delete") }
            }
        }
        if (visible.isEmpty()) Hint(if (query.isBlank()) "No thoughts here yet." else "No matching thoughts.")
        visible.forEach { thought ->
            ThoughtRow(thought, state.projects.find { it.id == thought.projectID }?.name, selecting, thought.id in selected, { if (selecting) selected = if (thought.id in selected) selected - thought.id else selected + thought.id else run(AppCommand.SetThoughtsCompleted(setOf(thought.id), thought.completedAt == null)) }, { if (selecting) selected = if (thought.id in selected) selected - thought.id else selected + thought.id else edit(thought) }, { selected = setOf(thought.id); deleting = true })
        }
    }
    if (deleting) Confirm("Delete thoughts?", "These thoughts will be removed. You can Undo briefly after deleting.", "Delete", { deleting = false }) { run(AppCommand.DeleteThoughts(selected)); selected = emptySet(); deleting = false }
}

@Composable private fun ThoughtRow(thought: CapturedThought, project: String?, selecting: Boolean = false, selected: Boolean = false, check: () -> Unit, edit: () -> Unit, delete: () -> Unit) {
    Surface(shape = MaterialTheme.shapes.medium, color = MaterialTheme.colorScheme.surfaceContainer) {
        Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked = if (selecting) selected else thought.completedAt != null, onCheckedChange = { check() })
            Column(Modifier.weight(1f).clickable(onClick = edit).padding(vertical = 10.dp)) { Text(thought.text, textDecoration = if (thought.completedAt != null) TextDecoration.LineThrough else null); project?.let { Hint(it) } }
            if (!selecting) IconButton(delete) { Icon(Icons.Outlined.Delete, "Delete thought") }
        }
    }
}

@Composable internal fun ThoughtComposer(state: AppSnapshot, context: ThoughtCaptureContext, dismiss: () -> Unit, execute: suspend (AppCommand) -> MutationResult) {
    var text by rememberSaveable(context.id) { mutableStateOf("") }
    var projectID by rememberSaveable(context.id) { mutableStateOf(context.projectID) }
    val initialIDs = remember(context.id) { state.thoughts.map { it.id }.toSet() }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var confirming by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<CapturedThought?>(null) }
    var deleting by remember { mutableStateOf<CapturedThought?>(null) }
    val scope = rememberCoroutineScope()
    val close = { if (!busy) { if (text.isNotBlank()) confirming = true else dismiss() } }
    val saved = state.thoughts.filter { if (context.originSessionID != null) it.originSessionID == context.originSessionID else it.id !in initialIDs }.sortedBy { it.createdAt }
    val run: (AppCommand) -> Unit = { command -> scope.launch { when (val result = execute(command)) { is MutationResult.Failure -> error = result.message; else -> {} } } }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.safeDrawingPadding().imePadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text(if (context.originSessionID == null) "New thoughts" else "Session thoughts", Modifier.weight(1f), style = MaterialTheme.typography.titleLarge); TextButton(close) { Text("Done") } }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    saved.forEach { thought -> ThoughtRow(thought, state.projects.find { it.id == thought.projectID }?.name, check = { run(AppCommand.SetThoughtsCompleted(setOf(thought.id), thought.completedAt == null)) }, edit = { editing = thought }, delete = { deleting = thought }) }
                    if (saved.isEmpty()) Hint("Capture a thought and return to your focus. Saved thoughts remain even if you discard the session.")
                }
                if (context.originSessionID == null) SelectMenu("Project", listOf("" to "Unassigned") + state.projects.map { it.id to it.name }, projectID ?: "") { projectID = it.takeIf(String::isNotEmpty) }
                else Hint(state.projects.find { it.id == context.projectID }?.name ?: "Session thoughts")
                OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth(), label = { Text("Add a thought…") }, maxLines = 4, enabled = !busy)
                if (SessionText.count(text) >= 450) Text("${SessionText.count(text)} / 500")
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Action("Add thought", !busy && text.isNotBlank() && SessionText.count(text) <= 500) { scope.launch { busy = true; val captured = if (context.originSessionID == null) context.copy(projectID = projectID) else context; when (val result = execute(AppCommand.CaptureThought(captured, text))) { MutationResult.Success -> { text = ""; error = null }; is MutationResult.Failure -> error = result.message }; busy = false } }
            }
        }
    }
    if (confirming) AlertDialog(onDismissRequest = { confirming = false }, title = { Text("Discard this draft?") }, text = { Text("Thoughts you've already added remain saved.") }, dismissButton = { TextButton({ confirming = false }) { Text("Keep editing") } }, confirmButton = { TextButton(dismiss) { Text("Discard draft") } })
    editing?.let { thought -> key(thought.id) { TextEditor("Edit thought", thought.text, 500, { editing = null }) { execute(AppCommand.EditThought(thought.id, it)) } } }
    deleting?.let { thought -> Confirm("Delete thought?", "You can Undo briefly after deleting.", "Delete", { deleting = null }) { run(AppCommand.DeleteThoughts(setOf(thought.id))); deleting = null } }
}
