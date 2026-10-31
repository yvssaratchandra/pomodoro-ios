package com.jamesblack.pomodoro.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.ui.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import kotlinx.coroutines.launch

/** Every accepted task operation persists the entire plan before adopting its candidate. */
@Composable internal fun PlanEditor(initial: String, dismiss: () -> Unit, title: String = "Session plan", save: suspend (String) -> MutationResult) {
    var accepted by rememberSaveable { mutableStateOf(initial) }
    var plan by rememberSaveable(stateSaver = listSaver<SessionPlanDraft, String>(save = { it.rows.flatMap { row -> listOf(row.id, row.text) } }, restore = { values -> SessionPlanDraft(values.chunked(2).map { SessionPlanDraft.Row(it[0], it[1]) }) })) { mutableStateOf(SessionPlanDraft(accepted)) }
    var input by rememberSaveable { mutableStateOf("") }
    var editingID by rememberSaveable { mutableStateOf<String?>(null) }
    var original by rememberSaveable { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirming by remember { mutableStateOf(false) }
    var deleteID by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val dirty = input != original
    val close = { if (!busy) { if (dirty) confirming = true else dismiss() } }
    val mutate: (SessionPlanDraft.Mutation) -> Unit = { mutation ->
        scope.launch {
            val candidate = try { plan.candidate(mutation) } catch (failure: IllegalArgumentException) { error = failure.message; null }
            if (candidate != null) {
                busy = true
                when (val result = save(candidate.text)) {
                    MutationResult.Success -> { plan = plan.adopt(candidate); accepted = candidate.text; input = ""; original = ""; editingID = null; error = null }
                    is MutationResult.Failure -> error = result.message
                }
                busy = false
            }
        }
    }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.safeDrawingPadding().imePadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleLarge); TextButton(close) { Text("Done") } }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (plan.rows.isEmpty()) Hint("Add a few tasks for this focus session.")
                    plan.rows.forEach { row -> Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("• ${row.text}", Modifier.weight(1f))
                        TextButton(enabled = !busy && !dirty, onClick = { editingID = row.id; original = row.text; input = row.text }) { Text("Edit") }
                        TextButton(enabled = !busy && !dirty, onClick = { deleteID = row.id }) { Text("Delete") }
                    } }
                }
                OutlinedTextField(input, { input = it }, Modifier.fillMaxWidth(), label = { Text(if (editingID == null) "Add a task" else "Edit task") }, maxLines = 4, enabled = !busy)
                Hint("${plan.characterCount} / 280 characters saved · one task per line")
                if (editingID != null) TextButton({ editingID = null; input = ""; original = "" }) { Text("Cancel task edit") }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Action(if (editingID == null) "Add task" else "Save task", !busy && input.isNotBlank()) { mutate(editingID?.let { SessionPlanDraft.Mutation.Edit(it, input) } ?: SessionPlanDraft.Mutation.Add(input)) }
            }
        }
    }
    if (confirming) AlertDialog(onDismissRequest = { confirming = false }, title = { Text("Discard unsaved task?") }, text = { Text("Tasks you've already saved will remain in the plan.") }, dismissButton = { TextButton({ confirming = false }) { Text("Keep editing") } }, confirmButton = { TextButton(dismiss) { Text("Discard draft") } })
    deleteID?.let { id -> Confirm("Delete task?", "This changes the saved session plan.", "Delete", { deleteID = null }) { mutate(SessionPlanDraft.Mutation.Delete(id)); deleteID = null } }
}
