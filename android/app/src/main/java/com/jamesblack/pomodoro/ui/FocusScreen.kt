package com.jamesblack.pomodoro.ui

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import kotlinx.coroutines.delay

@Composable internal fun FocusScreen(state: AppSnapshot, now: Double, selectedID: String?, select: (String) -> Unit, run: (AppCommand) -> Unit, create: () -> Unit, projects: () -> Unit, plan: (String) -> Unit, capture: (ThoughtCaptureContext) -> Unit, thoughts: (String) -> Unit, edit: (NoteRequest) -> Unit, platform: PlatformActions, editorOpen: Boolean) {
    val active = state.activeTimer
    val project = state.projects.find { it.id == (active?.projectID ?: selectedID) }
    val ongoing = state.projects.filter { it.status == ProjectStatus.ongoing }
    var confirmEnd by remember { mutableStateOf(false) }
    var dimEnabled by rememberSaveable { mutableStateOf(false) }
    var dimVisible by remember { mutableStateOf(false) }
    var revealGeneration by remember { mutableIntStateOf(0) }
    val context = LocalContext.current
    val accessibility = remember { context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager }
    var touchExploration by remember { mutableStateOf(accessibility.isTouchExplorationEnabled) }
    DisposableEffect(accessibility) { val listener = AccessibilityManager.TouchExplorationStateChangeListener { touchExploration = it }; accessibility.addTouchExplorationStateChangeListener(listener); onDispose { accessibility.removeTouchExplorationStateChangeListener(listener) } }
    LaunchedEffect(dimEnabled, active?.id, editorOpen, revealGeneration, touchExploration) { dimVisible = false; if (dimEnabled && active?.kind == TimerKind.focus && !editorOpen && !touchExploration && now < active.deadline) { delay(5000); dimVisible = true } }
    LaunchedEffect(active?.id) { if (active == null) { dimEnabled = false; dimVisible = false } }
    if (active != null && now >= active.deadline) dimVisible = false
    Page {
        if (active != null) {
            Text(state.projects.find { it.id == active.projectID }?.name ?: "Project", style = MaterialTheme.typography.titleLarge, modifier = Modifier.align(Alignment.CenterHorizontally))
            TimerFace(active.deadline - now, active.elapsed(now).toFloat() / active.plannedSeconds.coerceAtLeast(1), active.kind, Modifier.align(Alignment.CenterHorizontally))
            active.intention?.let { Text(it) }
            if (active.kind == TimerKind.focus) {
                TextButton({ edit(NoteRequest("Session plan", active.intention.orEmpty()) { AppCommand.EditIntention(active.id, true, it) }) }, Modifier.fillMaxWidth()) { Text(if (active.intention == null) "Add session plan" else "Edit session plan") }
                Action("End Focus") { confirmEnd = true }
                OutlinedButton({ capture(ThoughtCaptureContext(active.projectID, active.id)) }, Modifier.fillMaxWidth()) { Text("Add a thought") }
                Row(verticalAlignment = Alignment.CenterVertically) { Switch(dimEnabled, { dimEnabled = it }); Text("Dim Focus") }
                if (touchExploration) Hint("Dim Focus is paused while touch exploration is enabled.")
            } else {
                Action("End Break") { run(AppCommand.EndTimer) }
                OutlinedButton({ thoughts(active.projectID) }, Modifier.fillMaxWidth()) { Text("Review thoughts") }
                TextButton({ plan(active.projectID) }, Modifier.fillMaxWidth()) { Text("Plan next session") }
            }
        } else if (state.breakOffer != null) {
            val offer = requireNotNull(state.breakOffer)
            Text("Focus saved", style = MaterialTheme.typography.titleLarge)
            TimerFace(offer.minutes * 60.0, 0f, offer.kind, Modifier.align(Alignment.CenterHorizontally))
            MinuteControl("${offer.kind.title} duration", offer.minutes, 1, 60) { run(AppCommand.SetBreakDuration(offer, it)) }
            Action("Start ${offer.kind.title}") { platform.requestNotifications(); run(AppCommand.StartBreak) }
            TextButton({ run(AppCommand.SkipBreak) }, Modifier.fillMaxWidth()) { Text("Skip Break") }
            TextButton({ plan(offer.projectID) }, Modifier.fillMaxWidth()) { Text("Plan next session") }
            state.sessions.filter { it.projectID == offer.projectID }.maxByOrNull { it.endedAt }?.let { session -> TextButton({ edit(NoteRequest("Next step", session.nextStep.orEmpty()) { AppCommand.SaveNextStep(session.id, it, true) }) }, Modifier.fillMaxWidth()) { Text("Add next step") } }
        } else if (project == null || ongoing.isEmpty()) {
            Spacer(Modifier.height(30.dp)); Text(if (state.projects.isEmpty()) "Make space for focused work" else "Choose a project to continue", style = MaterialTheme.typography.headlineSmall)
            Hint("Create a project, then begin a focus session.")
            Action("Create Project", onClick = create)
            if (state.projects.isNotEmpty()) TextButton(projects, Modifier.fillMaxWidth()) { Text("Manage projects") }
        } else {
            SelectMenu("Project", ongoing.map { it.id to it.name }, project.id, select)
            TimerFace(project.preferredFocusMinutes * 60.0, 0f, TimerKind.focus, Modifier.align(Alignment.CenterHorizontally))
            MinuteControl("Focus duration", project.preferredFocusMinutes, 10, 60) { run(AppCommand.RememberFocusDuration(project.id, it)) }
            OutlinedButton({ plan(project.id) }, Modifier.fillMaxWidth()) { Text(if (project.breadcrumb == null) "Add session plan" else "${SessionPlanText.items(project.breadcrumb?.text).size} planned tasks") }
            project.breadcrumb?.let { Hint(it.text) }
            Action("Start Focus") { platform.requestNotifications(); run(AppCommand.StartFocus(project.id, project.preferredFocusMinutes)) }
            val target = GoalEngine.dailyTarget(project.id, now, state.goalPlan)
            val saved = Statistics.total(state, project.id, Statistics.today(now), now)
            Section("Today") { Text(DurationText.summary(saved), style = MaterialTheme.typography.headlineSmall); Hint(when (target) { null -> "No recorded goal"; 0 -> "Rest day"; else -> "of $target min" }); if (target != null && target > 0) LinearProgressIndicator(progress = { (saved / (target * 60)).toFloat().coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth()) }
        }
        if (platform.notificationStatus.isNotBlank()) Hint(platform.notificationStatus)
    }
    if (confirmEnd && active != null) AlertDialog(onDismissRequest = { confirmEnd = false }, title = { Text("End this focus session?") }, text = { Text("Save the time you've focused, or discard this session. Your thoughts remain saved.") }, confirmButton = { TextButton({ confirmEnd = false; run(AppCommand.EndTimer) }) { Text("Save Session") } }, dismissButton = { Column { TextButton({ confirmEnd = false }) { Text("Keep Focusing") }; TextButton({ confirmEnd = false; run(AppCommand.DiscardFocus(active.id)) }) { Text("Discard Session") } } })
    if (dimVisible && active != null) DimSurface(active, now, { dimVisible = false; revealGeneration++ }, { dimVisible = false; revealGeneration++; capture(ThoughtCaptureContext(active.projectID, active.id)) })
}
@Composable private fun TimerFace(seconds: Double, progress: Float, kind: TimerKind, modifier: Modifier = Modifier) {
    val accent = if (kind == TimerKind.focus) Indigo else Sage
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(200.dp), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(progress = { progress.coerceIn(0f, 1f) }, Modifier.fillMaxSize(), color = accent, strokeWidth = 8.dp, trackColor = accent.copy(alpha = .13f))
            Text(DurationText.countdown(seconds), fontSize = 58.sp, fontFamily = FontFamily.Monospace, color = accent, maxLines = 1)
        }
        Text(kind.title, color = accent, style = MaterialTheme.typography.titleMedium)
    }
}
@Composable private fun DimSurface(timer: ActiveTimer, now: Double, reveal: () -> Unit, capture: () -> Unit) {
    Dialog(onDismissRequest = reveal, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val view = LocalView.current
        DisposableEffect(view) { val previous = view.keepScreenOn; view.keepScreenOn = true; onDispose { view.keepScreenOn = previous } }
        Surface(Modifier.fillMaxSize(), color = Color.Black) {
            Box(Modifier.fillMaxSize().clickable(onClickLabel = "Reveal Focus", onClick = reveal)) {
                Row(Modifier.align(Alignment.Center).padding(horizontal = 32.dp), verticalAlignment = Alignment.CenterVertically) {
                    LinearProgressIndicator(progress = { (timer.elapsed(now) / timer.plannedSeconds.coerceAtLeast(1)).toFloat() }, color = Indigo.copy(alpha = .65f), trackColor = Indigo.copy(alpha = .12f), modifier = Modifier.weight(1f).height(3.dp).semantics { contentDescription = "Focus progress, ${DurationText.countdown(timer.deadline - now)} remaining" })
                    IconButton(capture) { Icon(Icons.Outlined.Add, "Capture thought", tint = Indigo.copy(alpha = .65f)) }
                }
            }
        }
    }
}
