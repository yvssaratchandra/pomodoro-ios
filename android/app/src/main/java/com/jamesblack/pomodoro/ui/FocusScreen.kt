package com.jamesblack.pomodoro.ui

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Brightness4
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import kotlinx.coroutines.delay

@Composable internal fun FocusScreen(
    state: AppSnapshot,
    now: Double,
    selectedID: String?,
    select: (String) -> Unit,
    run: (AppCommand) -> Unit,
    create: () -> Unit,
    projects: () -> Unit,
    settings: () -> Unit,
    plan: (String) -> Unit,
    capture: (ThoughtCaptureContext) -> Unit,
    thoughts: (String) -> Unit,
    edit: (NoteRequest) -> Unit,
    platform: PlatformActions,
    editorOpen: Boolean,
    dimEnabled: Boolean,
    setDimEnabled: (Boolean) -> Unit,
    execute: suspend (AppCommand) -> MutationResult
) {
    val active = state.activeTimer
    val project = state.projects.find { it.id == (active?.projectID ?: selectedID) }
    val ongoing = state.projects.filter { it.status == ProjectStatus.ongoing }
    var confirmEnd by remember { mutableStateOf(false) }
    var dimVisible by remember { mutableStateOf(false) }
    var revealGeneration by remember { mutableIntStateOf(0) }
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var resumed by remember { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, _ -> resumed = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val accessibility = remember { context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager }
    var touchExploration by remember { mutableStateOf(accessibility.isTouchExplorationEnabled) }
    DisposableEffect(accessibility) {
        val listener = AccessibilityManager.TouchExplorationStateChangeListener { touchExploration = it }
        accessibility.addTouchExplorationStateChangeListener(listener)
        onDispose { accessibility.removeTouchExplorationStateChangeListener(listener) }
    }

    LaunchedEffect(dimEnabled, active?.id, editorOpen, revealGeneration, touchExploration, resumed, confirmEnd) {
        dimVisible = false
        if (dimEnabled && active?.kind == TimerKind.focus && !editorOpen && !touchExploration && resumed && !confirmEnd && now < active.deadline) {
            if (revealGeneration > 0) delay(5000)
            dimVisible = true
        }
    }
    LaunchedEffect(dimEnabled) { if (dimEnabled) revealGeneration = 0 }
    LaunchedEffect(active?.id) { if (active == null) { setDimEnabled(false); dimVisible = false } }
    if (active != null && now >= active.deadline) dimVisible = false

    val headerTitle = when {
        active?.kind == TimerKind.focus -> "Focusing"
        active != null || state.breakOffer != null -> "Break"
        else -> "Focus"
    }
    Page(
        modifier = Modifier.pointerInput(dimEnabled) {
            awaitPointerEventScope {
                while (true) {
                    awaitPointerEvent()
                    if (dimEnabled) revealGeneration++
                }
            }
        },
        header = {
            ScreenHeader(
                title = headerTitle,
                leading = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(onClick = settings) { Icon(Icons.Outlined.Settings, contentDescription = "Settings") }
                        if (active?.kind == TimerKind.focus) {
                            IconButton(onClick = { setDimEnabled(!dimEnabled) }) {
                                Icon(Icons.Outlined.Brightness4, contentDescription = if (dimEnabled) "Disable Dim Focus" else "Enable Dim Focus")
                            }
                        }
                    }
                },
                trailing = {
                    IconButton(onClick = projects) { Icon(Icons.Outlined.FolderOpen, contentDescription = "Projects") }
                }
            )
        }
    ) {
        if (active != null) {
            Text(
                state.projects.find { it.id == active.projectID }?.name ?: "Project",
                modifier = Modifier.fillMaxWidth(),
                style = MaterialTheme.typography.titleLarge,
                textAlign = TextAlign.Center
            )
            val remaining = (active.deadline - now).coerceIn(0.0, active.plannedSeconds.toDouble())
            TimerFace(
                seconds = remaining,
                progress = (remaining / active.plannedSeconds.coerceAtLeast(1)).toFloat(),
                kind = active.kind,
                modifier = Modifier.align(Alignment.CenterHorizontally)
            )
            if (active.kind == TimerKind.focus) {
                DestructiveAction("End Focus") { confirmEnd = true }
                val currentPlan = active.intention?.let { "Session plan · ${SessionPlanText.items(it).size} tasks" } ?: "Add session plan"
                PlanRow(currentPlan) {
                    edit(NoteRequest("Session plan", active.intention.orEmpty()) { AppCommand.EditIntention(active.id, true, it) })
                }
                TextButton(
                    onClick = { capture(ThoughtCaptureContext(active.projectID, active.id)) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                ) {
                    Icon(Icons.Outlined.Add, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Add a thought")
                }
                if (touchExploration) Hint("Dim Focus is paused while touch exploration is enabled.")
            } else {
                OutlinedButton(
                    onClick = { run(AppCommand.EndTimer) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    shape = MaterialTheme.shapes.small,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.secondary)
                ) { Text("End Break") }
                PlanRow(planLabel(project), onClick = { plan(active.projectID) })
                TextButton(
                    onClick = { thoughts(active.projectID) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.secondary)
                ) { Text("Review thoughts") }
            }
        } else if (state.breakOffer != null) {
            val offer = requireNotNull(state.breakOffer)
            Text("Focus saved", style = MaterialTheme.typography.titleLarge)
            MinuteControl(
                "${offer.kind.title} duration",
                offer.minutes,
                1,
                60,
                onChange = {},
                save = { execute(AppCommand.SetBreakDuration(offer, it)) },
                trigger = { open ->
                    TimerTrigger("Edit ${offer.kind.title.lowercase()} duration", open) {
                        TimerFace(
                            seconds = offer.minutes * 60.0,
                            progress = 1f,
                            kind = offer.kind
                        )
                    }
                }
            )
            SageAction("Start ${offer.kind.title}") { run(AppCommand.StartBreak) }
            TextButton(
                onClick = { run(AppCommand.SkipBreak) },
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            ) { Text("Skip Break") }
            PlanRow(planLabel(state.projects.find { it.id == offer.projectID }), onClick = { plan(offer.projectID) })
        } else if (project == null || ongoing.isEmpty()) {
            Spacer(Modifier.height(10.dp))
            Text(
                if (state.projects.isEmpty()) "Make space for focused work" else "Choose a project to continue",
                style = MaterialTheme.typography.headlineSmall
            )
            Hint("Create a project, then begin a focus session.")
            Action("Create Project", onClick = create)
            if (state.projects.isNotEmpty()) {
                TextButton(onClick = projects, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("Manage projects") }
            }
        } else {
            ProjectSelector(ongoing, project, select)
            MinuteControl(
                "Focus duration",
                project.preferredFocusMinutes,
                10,
                60,
                onChange = {},
                save = { execute(AppCommand.RememberFocusDuration(project.id, it)) },
                trigger = { open ->
                    TimerTrigger("Edit focus duration", open) {
                        TimerFace(
                            seconds = project.preferredFocusMinutes * 60.0,
                            progress = 1f,
                            kind = TimerKind.focus
                        )
                    }
                }
            )
            Action("Start Focus") { run(AppCommand.StartFocus(project.id, project.preferredFocusMinutes)) }
            PlanRow(planLabel(project), onClick = { plan(project.id) })
        }
    }

    if (confirmEnd && active?.kind == TimerKind.focus) {
        AlertDialog(
            onDismissRequest = { confirmEnd = false },
            title = { Text("End this focus session?") },
            text = { Text("Save the time you've focused, or discard this session. Your thoughts remain saved.") },
            confirmButton = {
                TextButton(onClick = { confirmEnd = false; run(AppCommand.EndTimer) }) { Text("Save Session") }
            },
            dismissButton = {
                Column {
                    TextButton(onClick = { confirmEnd = false }) { Text("Keep Focusing") }
                    TextButton(onClick = { confirmEnd = false; run(AppCommand.DiscardFocus(active.id)) }) { Text("Discard Session") }
                }
            }
        )
    }
    if (dimVisible && active?.kind == TimerKind.focus) {
        DimSurface(
            active,
            now,
            { dimVisible = false; revealGeneration++ },
            { dimVisible = false; revealGeneration++; capture(ThoughtCaptureContext(active.projectID, active.id)) }
        )
    }
}

private fun planLabel(project: Project?): String = project?.breadcrumb?.let {
    "Session plan · ${SessionPlanText.items(it.text).size} tasks"
} ?: "Plan this session"

@Composable private fun PlanRow(label: String, onClick: () -> Unit) {
    TextButton(onClick, Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(label, Modifier.weight(1f), maxLines = 1)
            Text("›", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.titleLarge)
        }
    }
}

@Composable private fun DestructiveAction(label: String, onClick: () -> Unit) {
    val danger = MaterialTheme.colorScheme.error
    Button(
        onClick,
        Modifier.fillMaxWidth().heightIn(min = 48.dp),
        shape = MaterialTheme.shapes.small,
        colors = ButtonDefaults.buttonColors(containerColor = danger.copy(alpha = .1f), contentColor = danger)
    ) { Text(label, style = MaterialTheme.typography.bodyMedium) }
}

@Composable private fun SageAction(label: String, onClick: () -> Unit) {
    Button(
        onClick,
        Modifier.fillMaxWidth().heightIn(min = 48.dp),
        shape = MaterialTheme.shapes.small,
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.secondary,
            contentColor = if (MaterialTheme.colorScheme.background == Color.Black) Color.Black else Color.White
        )
    ) { Text(label, style = MaterialTheme.typography.bodyMedium) }
}

@Composable private fun TimerFace(seconds: Double, progress: Float, kind: TimerKind, modifier: Modifier = Modifier) {
    val accent = if (kind == TimerKind.focus) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.secondary
    val linear = LocalDensity.current.fontScale >= 1.3f
    val ringSemantics = Modifier
        .testTag("focus-timer")
        .semantics(mergeDescendants = true) {
            contentDescription = "${kind.title} time remaining"
            progressBarRangeInfo = ProgressBarRangeInfo(progress.coerceIn(0f, 1f), 0f..1f)
        }
    BoxWithConstraints(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        val useLinear = linear || maxWidth < 240.dp
        if (useLinear) {
            Column(
                ringSemantics.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        DurationText.countdown(seconds),
                        style = MaterialTheme.typography.displayMedium.copy(
                            fontWeight = FontWeight.SemiBold,
                            fontFeatureSettings = "tnum"
                        ),
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        softWrap = false
                    )
                    Text(kind.title, color = accent, style = MaterialTheme.typography.bodyMedium)
                }
                LinearProgressIndicator(
                    progress = { progress.coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth().height(8.dp),
                    color = accent,
                    trackColor = accent.copy(alpha = .13f)
                )
            }
        } else {
            Box(ringSemantics.size(200.dp), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(
                    progress = { progress.coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxSize(),
                    color = accent,
                    strokeWidth = 8.dp,
                    trackColor = accent.copy(alpha = .13f)
                )
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        DurationText.countdown(seconds),
                        style = MaterialTheme.typography.displayMedium.copy(
                            fontSize = 58.sp,
                            fontWeight = FontWeight.SemiBold,
                            fontFeatureSettings = "tnum",
                            letterSpacing = (-1.5).sp
                        ),
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        softWrap = false
                    )
                    Text(kind.title, color = accent, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

@Composable private fun ProjectSelector(projects: List<Project>, selected: Project, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .clickable(role = Role.Button, onClickLabel = "Choose project", onClick = { expanded = true })
                .padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Outlined.FolderOpen, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.width(12.dp))
            Text(selected.name, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, maxLines = 1)
            Text("⌄", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.titleMedium)
        }
        DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            projects.forEach { project ->
                DropdownMenuItem(
                    text = { Text(project.name) },
                    onClick = { expanded = false; onSelect(project.id) }
                )
            }
        }
    }
}

@Composable private fun TimerTrigger(label: String, open: () -> Unit, timer: @Composable () -> Unit) {
    Box(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClickLabel = label, onClick = open)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) { timer() }
}

@Composable private fun DimSurface(timer: ActiveTimer, now: Double, reveal: () -> Unit, capture: () -> Unit) {
    Dialog(onDismissRequest = reveal, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val view = LocalView.current
        DisposableEffect(view) { val previous = view.keepScreenOn; view.keepScreenOn = true; onDispose { view.keepScreenOn = previous } }
        Surface(Modifier.fillMaxSize(), color = Color.Black) {
            Box(Modifier.fillMaxSize().clickable(onClickLabel = "Reveal Focus", onClick = reveal)) {
                Row(Modifier.align(Alignment.Center).padding(horizontal = 32.dp), verticalAlignment = Alignment.CenterVertically) {
                    LinearProgressIndicator(
                        progress = { (timer.elapsed(now) / timer.plannedSeconds.coerceAtLeast(1)).toFloat() },
                        color = Indigo.copy(alpha = .65f),
                        trackColor = Indigo.copy(alpha = .12f),
                        modifier = Modifier.weight(1f).height(3.dp).semantics {
                            contentDescription = "Focus progress, ${DurationText.countdown((timer.deadline - now).coerceIn(0.0, timer.plannedSeconds.toDouble()))} remaining"
                        }
                    )
                    IconButton(capture) { Icon(Icons.Outlined.Add, "Capture thought", tint = Indigo.copy(alpha = .65f)) }
                }
            }
        }
    }
}
