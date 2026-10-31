package com.jamesblack.pomodoro.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*

internal val Indigo = Color(0xFF5856D6)
internal val Sage = Color(0xFF4E6B56)
internal val PomodoroBlue = Color(0xFF007AFF)
private val LightMuted = Color(0xFF636366)
private val DarkMuted = Color(0xFFAEAEB2)

@Composable internal fun PomodoroTheme(appearance: Appearance, content: @Composable () -> Unit) {
    val dark = appearance == Appearance.dark || (appearance == Appearance.system && isSystemInDarkTheme())
    val scheme = if (dark) {
        darkColorScheme(
            primary = Color(0xFF0A84FF),
            onPrimary = Color.Black,
            onSurface = Color(0xFFF2F2F7),
            onBackground = Color(0xFFF2F2F7),
            secondary = Color(0xFF84A08C),
            tertiary = Color(0xFF5E5CE6),
            background = Color.Black,
            surface = Color.Black,
            surfaceContainer = Color.Black,
            onSurfaceVariant = DarkMuted,
            error = Color(0xFFFF453A)
        )
    } else {
        lightColorScheme(
            primary = PomodoroBlue,
            onPrimary = Color.White,
            onSurface = Color(0xFF1C1C1E),
            onBackground = Color(0xFF1C1C1E),
            secondary = Sage,
            tertiary = Indigo,
            background = Color(0xFFF2F2F7),
            surface = Color.White,
            surfaceContainer = Color.White,
            onSurfaceVariant = LightMuted,
            error = Color(0xFFFF3B30)
        )
    }
    val typography = Typography(
        bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 24.sp),
        bodyMedium = TextStyle(fontSize = 16.sp, lineHeight = 23.sp),
        bodySmall = TextStyle(fontSize = 14.sp, lineHeight = 20.sp),
        titleMedium = TextStyle(fontSize = 17.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold),
        titleLarge = TextStyle(fontSize = 20.sp, lineHeight = 26.sp, fontWeight = FontWeight.SemiBold),
        headlineSmall = TextStyle(fontSize = 24.sp, lineHeight = 30.sp, fontWeight = FontWeight.SemiBold)
    )
    MaterialTheme(
        colorScheme = scheme,
        typography = typography,
        shapes = Shapes(
            small = RoundedCornerShape(10.dp),
            medium = RoundedCornerShape(10.dp),
            large = RoundedCornerShape(10.dp)
        ),
        content = content
    )
}

@Composable internal fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        Text(
            title,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 16.dp)
        )
        Surface(shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
        }
    }
}

@Composable internal fun GroupedSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        Text(
            title,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 16.dp)
        )
        Surface(shape = RoundedCornerShape(10.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
            Column(Modifier.fillMaxWidth(), content = content)
        }
    }
}

@Composable internal fun Page(
    modifier: Modifier = Modifier,
    header: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(modifier.fillMaxSize()) {
        if (header != null) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 20.dp)) {
                header()
            }
        }
        Column(
            Modifier
                .fillMaxWidth()
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 20.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
            content = content
        )
    }
}

@Composable internal fun ScreenHeader(
    title: String,
    largeTitle: Boolean = false,
    leading: @Composable () -> Unit = {},
    trailing: @Composable () -> Unit = {}
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(if (largeTitle) 8.dp else 0.dp)) {
        Box(Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
            Box(Modifier.align(Alignment.CenterStart).defaultMinSize(minWidth = 48.dp, minHeight = 48.dp), contentAlignment = Alignment.CenterStart) {
                CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.primary) { leading() }
            }
            if (!largeTitle) {
                Text(
                    title,
                    modifier = Modifier.align(Alignment.Center).padding(horizontal = 56.dp),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Box(Modifier.align(Alignment.CenterEnd).defaultMinSize(minWidth = 48.dp, minHeight = 48.dp), contentAlignment = Alignment.CenterEnd) {
                CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.primary) { trailing() }
            }
        }
        if (largeTitle) {
            Text(
                title,
                style = MaterialTheme.typography.headlineLarge.copy(fontSize = 34.sp, lineHeight = 40.sp, fontWeight = FontWeight.Bold),
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable internal fun GroupedRow(
    label: String,
    value: String? = null,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null
) {
    val rowModifier = modifier
        .fillMaxWidth()
        .heightIn(min = 48.dp)
        .then(if (onClick == null) Modifier else Modifier.clickable(enabled = enabled, role = Role.Button, onClick = onClick))
        .padding(vertical = 7.dp)
    Row(rowModifier, verticalAlignment = Alignment.CenterVertically) {
        Text(
            label,
            modifier = Modifier.weight(1f),
            color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = .38f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis
        )
        value?.let {
            Text(
                it,
                modifier = Modifier.widthIn(max = 140.dp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
        }
        if (onClick != null) {
            Text("›", Modifier.padding(start = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.titleLarge)
        }
    }
}

@Composable internal fun SegmentedSelector(
    options: List<Pair<String, String>>,
    selected: String,
    onSelect: (String) -> Unit
) {
    val trackColor = if (MaterialTheme.colorScheme.background == Color.Black) Color(0xFF1C1C1E) else Color(0xFFE5E5EA)
    val selectedColor = if (MaterialTheme.colorScheme.background == Color.Black) Color(0xFF3A3A3C) else Color.White
    Row(
        Modifier.fillMaxWidth().background(trackColor, RoundedCornerShape(8.dp)).padding(2.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        options.forEach { (key, label) ->
            val isSelected = key == selected
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = 48.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .then(if (isSelected) Modifier.background(selectedColor) else Modifier)
                    .selectable(selected = isSelected, role = Role.RadioButton, onClick = { onSelect(key) })
                    .padding(horizontal = 6.dp, vertical = 8.dp),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    label,
                    style = if (isSelected) MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold) else MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable internal fun Hint(text: String) { Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
@Composable internal fun Action(label: String, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick,
        Modifier.fillMaxWidth().heightIn(min = 48.dp),
        enabled = enabled,
        shape = RoundedCornerShape(10.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp)
    ) { Text(label, style = MaterialTheme.typography.bodyMedium) }
}
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

@Composable internal fun MinuteControl(
    label: String,
    value: Int,
    min: Int,
    max: Int,
    modifier: Modifier = Modifier,
    trigger: (@Composable (open: () -> Unit) -> Unit)? = null,
    save: (suspend (Int) -> MutationResult)? = null,
    onChange: (Int) -> Unit
) {
    var editing by rememberSaveable { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    var draft by rememberSaveable(value) { mutableStateOf(value.toString()) }
    if (trigger == null) {
        TextButton({ editing = true }, modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("$label · $value min") }
    } else {
        trigger { editing = true }
    }
    if (editing) AlertDialog(onDismissRequest = { editing = false }, title = { Text(label) }, text = { Column { OutlinedTextField(draft, { draft = it.filter(Char::isDigit).take(max.toString().length) }, label = { Text("Minutes ($min–$max)") }, keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number)); if (min == 0) Hint("0 means a rest day."); error?.let { Text(it, color = MaterialTheme.colorScheme.error) } } }, dismissButton = { TextButton({ editing = false }) { Text("Cancel") } }, confirmButton = { TextButton(enabled = !busy && draft.toIntOrNull()?.let { it in min..max } == true, onClick = { if (save == null) { onChange(draft.toInt()); editing = false } else scope.launch { busy = true; when (val result = save(draft.toInt())) { MutationResult.Success -> editing = false; is MutationResult.Failure -> error = result.message }; busy = false } }) { Text("Done") } })
}

@Composable
internal fun ChoiceRow(
    label: String,
    selected: String,
    options: List<Pair<String, String>>,
    enabled: Boolean = true,
    onSelect: (String) -> Unit
) {
    var expanded by rememberSaveable(label) { mutableStateOf(false) }
    GroupedRow(label, selected, enabled = enabled, onClick = { expanded = true })
    if (expanded) {
        AlertDialog(
            onDismissRequest = { expanded = false },
            title = { Text(label) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    options.forEach { (key, value) ->
                        TextButton(onClick = { expanded = false; onSelect(key) }, modifier = Modifier.fillMaxWidth()) {
                            Text(if (value == selected) "$value ✓" else value, modifier = Modifier.fillMaxWidth())
                        }
                    }
                }
            },
            confirmButton = { TextButton(onClick = { expanded = false }) { Text("Done") } }
        )
    }
}

@Composable internal fun InsetGroupedRow(
    label: String,
    value: String? = null,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null
) {
    GroupedRow(label, value, enabled, modifier = Modifier.padding(horizontal = 16.dp), onClick = onClick)
}
