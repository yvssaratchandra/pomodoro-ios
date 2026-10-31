package com.jamesblack.pomodoro.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import kotlinx.coroutines.launch

/** Every accepted task operation persists the entire plan before adopting its candidate. */
@Composable
internal fun PlanEditor(
    initial: String,
    dismiss: () -> Unit,
    title: String = "Session plan",
    save: suspend (String) -> MutationResult
) {
    var accepted by rememberSaveable { mutableStateOf(initial) }
    var plan by rememberSaveable(
        stateSaver = listSaver<SessionPlanDraft, String>(
            save = { it.rows.flatMap { row -> listOf(row.id, row.text) } },
            restore = { values -> SessionPlanDraft(values.chunked(2).map { SessionPlanDraft.Row(it[0], it[1]) }) }
        )
    ) { mutableStateOf(SessionPlanDraft(accepted)) }
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

    suspend fun persistMutation(mutation: SessionPlanDraft.Mutation): Boolean {
        val candidate = try {
            plan.candidate(mutation)
        } catch (failure: IllegalArgumentException) {
            error = failure.message
            return false
        }
        return when (val result = save(candidate.text)) {
            MutationResult.Success -> {
                plan = plan.adopt(candidate)
                accepted = candidate.text
                input = ""
                original = ""
                editingID = null
                error = null
                true
            }
            is MutationResult.Failure -> {
                error = result.message
                false
            }
        }
    }

    val mutate: (SessionPlanDraft.Mutation) -> Unit = { mutation ->
        scope.launch {
            if (!busy) {
                busy = true
                persistMutation(mutation)
                busy = false
            }
        }
    }

    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Page(
                modifier = Modifier.safeDrawingPadding().imePadding(),
                header = {
                    ScreenHeader(
                        title = title,
                        leading = { TextButton(onClick = close, modifier = Modifier.heightIn(min = 48.dp)) { Text("Cancel") } },
                        trailing = { TextButton(onClick = close, modifier = Modifier.heightIn(min = 48.dp)) { Text("Done") } }
                    )
                }
            ) {
                GroupedSection("Tasks") {
                    if (plan.rows.isEmpty()) {
                        Box(Modifier.padding(16.dp)) { Hint("Add a few tasks for this focus session.") }
                    }
                    plan.rows.forEachIndexed { index, row ->
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp, vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text("• ${row.text}", Modifier.weight(1f))
                            TextButton(
                                enabled = !busy && !dirty,
                                onClick = { editingID = row.id; original = row.text; input = row.text },
                                modifier = Modifier.heightIn(min = 48.dp)
                            ) { Text("Edit") }
                            TextButton(
                                enabled = !busy && !dirty,
                                onClick = { deleteID = row.id; error = null },
                                modifier = Modifier.heightIn(min = 48.dp)
                            ) { Text("Delete", color = MaterialTheme.colorScheme.error) }
                        }
                        if (index != plan.rows.lastIndex) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                    }
                }
                OutlinedTextField(
                    value = input,
                    onValueChange = { input = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(if (editingID == null) "Add a task" else "Edit task") },
                    maxLines = 4,
                    enabled = !busy
                )
                Hint("${plan.characterCount} / 280 characters saved · one task per line")
                if (editingID != null) {
                    TextButton(
                        onClick = { editingID = null; input = ""; original = "" },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                    ) { Text("Cancel task edit") }
                }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Action(if (editingID == null) "Add task" else "Save task", !busy && input.isNotBlank()) {
                    mutate(editingID?.let { SessionPlanDraft.Mutation.Edit(it, input) } ?: SessionPlanDraft.Mutation.Add(input))
                }
            }
        }
    }

    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text("Discard unsaved task?") },
            text = { Text("Tasks you've already saved will remain in the plan.") },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text("Keep editing") } },
            confirmButton = {
                TextButton(onClick = {
                    confirming = false
                    input = original
                    editingID = null
                    dismiss()
                }) { Text("Discard draft") }
            }
        )
    }

    deleteID?.let { id ->
        AlertDialog(
            onDismissRequest = { if (!busy) deleteID = null },
            title = { Text("Delete task?") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("This changes the saved session plan.")
                    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteID = null }, enabled = !busy) { Text("Cancel") }
            },
            confirmButton = {
                TextButton(
                    enabled = !busy,
                    onClick = {
                        scope.launch {
                            busy = true
                            if (persistMutation(SessionPlanDraft.Mutation.Delete(id))) deleteID = null
                            busy = false
                        }
                    }
                ) { Text("Delete", color = MaterialTheme.colorScheme.error) }
            }
        )
    }
}
