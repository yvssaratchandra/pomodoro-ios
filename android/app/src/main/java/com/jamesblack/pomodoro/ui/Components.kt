package com.jamesblack.pomodoro.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*

internal val Indigo = Color(0xFF6860D8)
internal val Sage = Color(0xFF789681)

@Composable internal fun PomodoroTheme(appearance: Appearance, content: @Composable () -> Unit) {
    val dark = appearance == Appearance.dark || (appearance == Appearance.system && isSystemInDarkTheme())
    val scheme = if (dark) darkColorScheme(primary = Indigo, secondary = Sage, background = Color.Black, surface = Color.Black, surfaceContainer = Color(0xFF171719))
    else lightColorScheme(primary = Indigo, secondary = Sage, background = Color(0xFFF6F5FA), surface = Color(0xFFF6F5FA), surfaceContainer = Color.White)
    MaterialTheme(colorScheme = scheme, shapes = Shapes(medium = RoundedCornerShape(16.dp), large = RoundedCornerShape(22.dp)), content = content)
}

@Composable internal fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Surface(shape = RoundedCornerShape(18.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
        }
    }
}
@Composable internal fun Page(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp), content = content)
}
@Composable internal fun Hint(text: String) { Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
@Composable internal fun Action(label: String, enabled: Boolean = true, onClick: () -> Unit) { Button(onClick, Modifier.fillMaxWidth().heightIn(min = 48.dp), enabled = enabled) { Text(label) } }
@Composable internal fun SelectMenu(label: String, choices: List<Pair<String, String>>, selected: String?, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton({ expanded = true }, Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("$label: ${choices.find { it.first == selected }?.second ?: "All"}") }
        DropdownMenu(expanded, { expanded = false }) { choices.forEach { (id, name) -> DropdownMenuItem(text = { Text(name) }, onClick = { expanded = false; onSelect(id) }) } }
    }
}
@Composable internal fun Confirm(title: String, message: String, action: String, onDismiss: () -> Unit, onConfirm: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text(title) }, text = { Text(message) }, dismissButton = { TextButton(onDismiss) { Text("Cancel") } }, confirmButton = { TextButton(onConfirm) { Text(action) } })
}

/** Owns only a draft. A failed command keeps the editor and its text intact. */
@Composable internal fun TextEditor(title: String, initial: String, limit: Int, onDismiss: () -> Unit, save: suspend (String) -> MutationResult) {
    var text by rememberSaveable { mutableStateOf(initial) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirming by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val dismiss = { if (!saving) { if (text != initial) confirming = true else onDismiss() } }
    Dialog(onDismissRequest = dismiss, properties = DialogProperties(usePlatformDefaultWidth = false, dismissOnBackPress = true)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column(Modifier.safeDrawingPadding().imePadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(dismiss) { Text("Cancel") }
                    Text(title, Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                    TextButton(enabled = !saving && SessionText.count(text) <= limit, onClick = { scope.launch { saving = true; when (val result = save(text)) { MutationResult.Success -> onDismiss(); is MutationResult.Failure -> error = result.message }; saving = false } }) { Text("Save") }
                }
                OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth().weight(1f), placeholder = { Text(if (limit == 280) "One task per line" else "What's on your mind?") }, enabled = !saving)
                Text("${SessionText.count(text)} / $limit", color = if (SessionText.count(text) > limit) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        }
    }
    if (confirming) AlertDialog(onDismissRequest = { confirming = false }, title = { Text("Discard changes?") }, text = { Text("Your unsaved text will be lost.") }, dismissButton = { TextButton({ confirming = false }) { Text("Keep editing") } }, confirmButton = { TextButton(onDismiss) { Text("Discard") } })
}

@Composable internal fun MinuteControl(label: String, value: Int, min: Int, max: Int, onChange: (Int) -> Unit) {
    var editing by remember { mutableStateOf(false) }
    var draft by rememberSaveable(value) { mutableStateOf(value.toString()) }
    TextButton({ editing = true }, Modifier.fillMaxWidth()) { Text("$label · $value min") }
    if (editing) AlertDialog(onDismissRequest = { editing = false }, title = { Text(label) }, text = { Column { OutlinedTextField(draft, { draft = it.filter(Char::isDigit).take(4) }, label = { Text("Minutes ($min–$max)") }, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number)); if (min == 0) Hint("0 means a rest day.") } }, dismissButton = { TextButton({ editing = false }) { Text("Cancel") } }, confirmButton = { TextButton(enabled = draft.toIntOrNull()?.let { it in min..max } == true, onClick = { onChange(draft.toInt()); editing = false }) { Text("Done") } })
}
