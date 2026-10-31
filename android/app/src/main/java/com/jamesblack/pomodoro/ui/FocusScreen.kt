package com.jamesblack.pomodoro.ui

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Contrast
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.draw.clip
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
                        if (active?.kind == TimerKind.focus) {
                            IconButton(
                                onClick = { setDimEnabled(!dimEnabled) },
                                modifier = Modifier.size(48.dp)
                            ) {
                                Icon(
                                    Icons.Outlined.Contrast,
                                    contentDescription = if (dimEnabled) "Disable Dim Focus" else "Enable Dim Focus",
                                    modifier = Modifier.size(24.dp),
                                    tint = if (dimEnabled) Indigo else MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                        IconButton(onClick = settings, modifier = Modifier.size(48.dp)) {
                            Icon(Icons.Outlined.Settings, contentDescription = "Settings", modifier = Modifier.size(24.dp))
                        }
                    }
                },
                trailing = {
                    IconButton(onClick = projects, modifier = Modifier.size(48.dp)) {
                        Icon(Icons.Outlined.Folder, contentDescription = "Projects", modifier = Modifier.size(24.dp))
                    }
                }
            )
        }
    ) {
        if (active != null) {
            Text(
                state.projects.find { it.id == active.projectID }?.name ?: "Project",
                modifier = Modifier.fillMaxWidth(),
                style = MaterialTheme.typography.titleMedium,
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
                DestructiveAction("End Focus", Icons.Filled.Stop) { confirmEnd = true }
                val taskCount = SessionPlanText.items(active.intention.orEmpty()).size
                PlanRow("Session plan", taskCount) {
                    edit(NoteRequest("Session plan", active.intention.orEmpty()) { AppCommand.EditIntention(active.id, true, it) })
                }
                TextButton(
                    onClick = { capture(ThoughtCaptureContext(active.projectID, active.id)) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                ) {
                    Icon(Icons.Outlined.ChatBubbleOutline, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("Add a thought")
                }
                if (touchExploration) Hint("Dim Focus is paused while touch exploration is enabled.")
            } else {
                OutlinedButton(
                    onClick = { run(AppCommand.EndTimer) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp),
                    shape = MaterialTheme.shapes.small,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.secondary)
                ) {
                    Icon(Icons.Filled.Stop, contentDescription = null, modifier = Modifier.size(20.dp))
                    Spacer(Modifier.width(8.dp))
                    Text("End Break")
                }
                val taskCount = project?.breadcrumb?.let { SessionPlanText.items(it.text).size } ?: 0
                PlanRow("Plan next session", taskCount, onClick = { plan(active.projectID) })
                TextButton(
                    onClick = { thoughts(active.projectID) },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.secondary)
                ) { Text("Review thoughts") }
            }
        } else if (state.breakOffer != null) {
            val offer = requireNotNull(state.breakOffer)
            Text("Focus saved", modifier = Modifier.fillMaxWidth(), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
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
                            kind = offer.kind,
                            project = state.projects.find { it.id == offer.projectID }?.name,
                            showEditCue = true
                        )
                    }
                }
            )
            SageAction("Start Break", Icons.Filled.LocalCafe) { run(AppCommand.StartBreak) }
            TextButton(
                onClick = { run(AppCommand.SkipBreak) },
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
            ) { Text("Skip Break") }
            val taskCount = state.projects.find { it.id == offer.projectID }?.breadcrumb?.let { SessionPlanText.items(it.text).size } ?: 0
            PlanRow("Plan next session", taskCount, onClick = { plan(offer.projectID) })
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
            ProjectSelector(ongoing, project, select, create, projects)
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
                            kind = TimerKind.focus,
                            showEditCue = true
                        )
                    }
                }
            )
            Button(
                onClick = { run(AppCommand.StartFocus(project.id, project.preferredFocusMinutes)) },
                modifier = Modifier.fillMaxWidth().heightIn(min = 64.dp),
                shape = MaterialTheme.shapes.small,
                colors = ButtonDefaults.buttonColors(contentColor = Color.White),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp)
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text("Start Focus", style = MaterialTheme.typography.bodyMedium)
            }
            val taskCount = project.breadcrumb?.let { SessionPlanText.items(it.text).size } ?: 0
            PlanRow(if (taskCount == 0) "Plan this session" else "Session plan", taskCount, onClick = { plan(project.id) })
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

@Composable private fun PlanRow(title: String, taskCount: Int, onClick: () -> Unit) {
    val label = if (taskCount > 0) "$title · $taskCount ${if (taskCount == 1) "task" else "tasks"}" else title
    TextButton(
        onClick,
        Modifier.fillMaxWidth().heightIn(min = 48.dp),
        contentPadding = PaddingValues(horizontal = 0.dp, vertical = 8.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                label,
                Modifier.weight(1f),
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1
            )
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable private fun DestructiveAction(label: String, icon: ImageVector, onClick: () -> Unit) {
    val danger = MaterialTheme.colorScheme.error
    Button(
        onClick,
        Modifier.fillMaxWidth().heightIn(min = 64.dp),
        shape = MaterialTheme.shapes.small,
        colors = ButtonDefaults.buttonColors(containerColor = if (MaterialTheme.colorScheme.background == Color.Black) Color(0xFF262628) else Color(0xFFE5E5EA), contentColor = danger)
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable private fun SageAction(label: String, icon: ImageVector, onClick: () -> Unit) {
    Button(
        onClick,
        Modifier.fillMaxWidth().heightIn(min = 64.dp),
        shape = MaterialTheme.shapes.small,
        colors = ButtonDefaults.buttonColors(
            containerColor = MaterialTheme.colorScheme.secondary,
            contentColor = if (MaterialTheme.colorScheme.background == Color.Black) Color.Black else Color.White
        )
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(label, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable private fun TimerFace(
    seconds: Double,
    progress: Float,
    kind: TimerKind,
    modifier: Modifier = Modifier,
    project: String? = null,
    showEditCue: Boolean = false
) {
    val accent = if (kind == TimerKind.focus) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.secondary
    val linear = LocalDensity.current.fontScale >= 1.3f
    val ringSemantics = Modifier
        .testTag("focus-timer")
        .semantics(mergeDescendants = true) {
            contentDescription = "${kind.title} time remaining"
            progressBarRangeInfo = ProgressBarRangeInfo(progress.coerceIn(0f, 1f), 0f..1f)
        }
    BoxWithConstraints(modifier.fillMaxWidth().padding(top = 4.dp), contentAlignment = Alignment.Center) {
        val useLinear = linear || maxWidth < 224.dp
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (useLinear) {
                Column(
                    ringSemantics.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        DurationText.countdown(seconds),
                        style = MaterialTheme.typography.displayMedium.copy(
                            fontFamily = TimerFontFamily,
                            fontWeight = FontWeight.ExtraBold,
                            fontFeatureSettings = "tnum"
                        ),
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        softWrap = false
                    )
                    if (showEditCue) {
                        Icon(
                            Icons.Outlined.Edit,
                            contentDescription = null,
                            modifier = Modifier.size(13.dp).testTag("duration-edit-cue"),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                    LinearProgressIndicator(
                        progress = { progress.coerceIn(0f, 1f) },
                        modifier = Modifier.fillMaxWidth().height(8.dp),
                        color = accent,
                        trackColor = accent.copy(alpha = .13f)
                    )
                }
            } else {
                Box(ringSemantics.size(212.dp), contentAlignment = Alignment.Center) {
                    val fill = if (MaterialTheme.colorScheme.background == Color.Black) {
                        Color.Black
                    } else {
                        accent.copy(alpha = .04f)
                    }
                    Box(
                        Modifier.size(200.dp).clip(CircleShape).background(fill)
                    )
                    Canvas(Modifier.size(208.dp)) {
                        val stroke = 8.dp.toPx()
                        val inset = stroke / 2
                        val arcSize = Size(size.width - stroke, size.height - stroke)
                        drawArc(
                            color = accent.copy(alpha = .12f), startAngle = -90f, sweepAngle = 360f,
                            useCenter = false, topLeft = Offset(inset, inset), size = arcSize,
                            style = Stroke(stroke)
                        )
                        drawArc(
                            brush = Brush.linearGradient(listOf(lerp(accent, Color.White, .18f), accent)),
                            startAngle = -90f, sweepAngle = 360f * progress.coerceIn(0f, 1f),
                            useCenter = false, topLeft = Offset(inset, inset), size = arcSize,
                            style = Stroke(stroke, cap = StrokeCap.Round)
                        )
                    }
                    Text(
                        DurationText.countdown(seconds),
                        style = MaterialTheme.typography.displayMedium.copy(
                            fontFamily = TimerFontFamily,
                            fontSize = 58.sp,
                            lineHeight = 64.sp,
                            fontWeight = FontWeight.ExtraBold,
                            fontFeatureSettings = "tnum"
                        ),
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 1,
                        softWrap = false
                    )
                    if (showEditCue) {
                        Icon(
                            Icons.Outlined.Edit,
                            contentDescription = null,
                            modifier = Modifier.align(Alignment.Center).offset(y = 47.dp).size(13.dp).testTag("duration-edit-cue"),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
            project?.takeIf(String::isNotBlank)?.let {
                Text(
                    it,
                    modifier = Modifier.fillMaxWidth(),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}

@Composable private fun ProjectSelector(
    projects: List<Project>,
    selected: Project,
    onSelect: (String) -> Unit,
    onCreate: () -> Unit,
    onManage: () -> Unit
) {
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
            Icon(Icons.Outlined.Folder, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(12.dp))
            Text(selected.name, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary, maxLines = 1)
            Icon(Icons.Outlined.UnfoldMore, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
        }
        DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            projects.forEach { project ->
                DropdownMenuItem(
                    text = { Text(project.name) },
                    onClick = { expanded = false; onSelect(project.id) }
                )
            }
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text("New project") },
                leadingIcon = { Icon(Icons.Outlined.Add, contentDescription = null) },
                onClick = { expanded = false; onCreate() }
            )
            DropdownMenuItem(
                text = { Text("Manage projects") },
                leadingIcon = { Icon(Icons.Outlined.Folder, contentDescription = null) },
                onClick = { expanded = false; onManage() }
            )
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
