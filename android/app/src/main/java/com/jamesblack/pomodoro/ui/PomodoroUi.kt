package com.jamesblack.pomodoro.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*

internal class UiEditors : ViewModel() {
    var dimEnabled by mutableStateOf(false)
    var project by mutableStateOf<ProjectDraft?>(null)
    var note by mutableStateOf<NoteRequest?>(null)
    var capture by mutableStateOf<ThoughtCaptureContext?>(null)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun PomodoroUi(snapshot: AppSnapshot, now: Double, undo: PendingDeletion?, error: String?, route: AppRoute?, onRouteHandled: () -> Unit, execute: suspend (AppCommand) -> MutationResult, platform: PlatformActions, onDismissError: () -> Unit = {}) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var destination by rememberSaveable { mutableStateOf<String?>(null) }
    var projectsFromSettings by rememberSaveable { mutableStateOf(false) }
    var selectedProject by rememberSaveable { mutableStateOf<String?>(null) }
    var thoughtsProject by rememberSaveable { mutableStateOf<String?>(null) }
    val editors: UiEditors = viewModel()
    var projectEditor by editors::project
    var note by editors::note
    var capture by editors::capture
    val pageState = rememberSaveableStateHolder()
    var sessionID by rememberSaveable { mutableStateOf<String?>(null) }
    var localError by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val run: (AppCommand) -> Unit = { command -> scope.launch { if (execute(command) is MutationResult.Failure) { /* Root also presents store errors. */ } } }
    val plan: (String) -> Unit = { id -> snapshot.projects.find { it.id == id }?.let { p -> note = NoteRequest("Session plan", p.breadcrumb?.text.orEmpty()) { AppCommand.SetPendingPlan(id, it) } } }
    val openCapture: (ThoughtCaptureContext) -> Unit = { context -> if (capture == null) capture = context }
    val create = { projectEditor = ProjectDraft.from(snapshot, now = now) }
    val editorOpen = note != null || capture != null || projectEditor != null || sessionID != null
    LaunchedEffect(snapshot.projects) { if (snapshot.projects.none { it.id == selectedProject && it.status == ProjectStatus.ongoing }) selectedProject = snapshot.projects.firstOrNull { it.status == ProjectStatus.ongoing }?.id }
    LaunchedEffect(route, editorOpen) {
        if (route != null && !editorOpen) {
            projectsFromSettings = false
            when (route) {
                AppRoute.Timer -> { tab = 0; destination = null; projectsFromSettings = false }
                AppRoute.NewProject -> { tab = 0; destination = null; projectsFromSettings = false; create() }
                is AppRoute.StartFocus -> { tab = 0; destination = null; projectsFromSettings = false; val project = snapshot.projects.find { it.id == route.projectID }; execute(AppCommand.Reconcile); if ((snapshot.activeTimer == null || snapshot.activeTimer!!.deadline <= now) && project?.status == ProjectStatus.ongoing) { selectedProject = project.id; execute(AppCommand.StartFocus(project.id, project.preferredFocusMinutes)) } else if (project == null || project.status != ProjectStatus.ongoing) localError = "This project is no longer available for Focus." else localError = "A timer is already running." }
                is AppRoute.CaptureThought -> {
                    val active = snapshot.activeTimer?.takeIf { it.kind == TimerKind.focus && now < it.deadline && (route.sessionID == null || it.id == route.sessionID) }
                    val saved = snapshot.sessions.find { it.id == route.sessionID }
                    openCapture(ThoughtCaptureContext(projectID = active?.projectID ?: saved?.projectID, originSessionID = active?.id ?: saved?.id))
                }
                is AppRoute.PlanNextSession -> if (snapshot.projects.any { it.id == route.projectID }) plan(route.projectID) else localError = "This project is no longer available."
            }
            onRouteHandled()
        } else if (route is AppRoute.CaptureThought && capture != null) {
            // Repeated capture links never replace a composer or its draft.
            onRouteHandled()
        }
    }
    PomodoroTheme(snapshot.settings.appearance) {
        BackHandler(destination != null && !editorOpen) {
            if (destination == "projects" && projectsFromSettings) {
                destination = "settings"
                projectsFromSettings = false
            } else {
                destination = null
                projectsFromSettings = false
            }
        }

        Scaffold(bottomBar = {
            Column {
                if (undo != null) Snackbar(action = { TextButton({ run(AppCommand.UndoDeletion) }) { Text("Undo") } }, dismissAction = { IconButton({ run(AppCommand.DismissUndo) }) { Icon(Icons.Outlined.Close, "Dismiss Undo") } }) { Text("${undo.count} ${if (undo.count == 1) "item" else "items"} deleted") }
                val labels = listOf("Focus", "Thoughts", "Stats")
                val icons = listOf(Icons.Outlined.Timer, Icons.AutoMirrored.Filled.Chat, Icons.Filled.BarChart)
                HorizontalDivider(thickness = 0.5.dp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = .12f))
                Row(
                    Modifier
                        .fillMaxWidth()
                        .background(MaterialTheme.colorScheme.background)
                        .navigationBarsPadding()
                        .padding(horizontal = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    labels.forEachIndexed { index, label ->
                        val selected = tab == index
                        Column(
                            Modifier
                                .weight(1f)
                                .heightIn(min = 56.dp)
                                .selectable(
                                    selected = selected,
                                    role = Role.Tab,
                                    onClick = { tab = index; destination = null; projectsFromSettings = false }
                                )
                                .testTag("tab-${label.lowercase()}"),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center
                        ) {
                            Icon(
                                icons[index],
                                contentDescription = null,
                                tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(28.dp)
                            )
                            Text(
                                label,
                                color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.sp, lineHeight = 14.sp),
                                maxLines = 1
                            )
                        }
                    }
                }
            }
        }) { padding ->
            Box(Modifier.padding(padding)) {
              pageState.SaveableStateProvider(destination ?: "tab$tab") {
                when (destination) {
                    "projects" -> ProjectsScreen(
                        snapshot, now, run,
                        { projectEditor = ProjectDraft.from(snapshot, it, now) },
                        create,
                        { selectedProject = it; destination = null; projectsFromSettings = false; tab = 0 },
                        { thoughtsProject = it; destination = null; projectsFromSettings = false; tab = 1 },
                        { sessionID = it }, platform, execute,
                        onExit = { destination = if (projectsFromSettings) "settings" else null; projectsFromSettings = false },
                        openPlan = plan
                    )
                    "settings" -> SettingsScreen(
                        snapshot, platform, run, execute,
                        onExit = { destination = null; projectsFromSettings = false },
                        openProjects = { projectsFromSettings = true; destination = "projects" }
                    )
                    else -> when (tab) {
                        0 -> FocusScreen(
                            state = snapshot,
                            now = now,
                            selectedID = selectedProject,
                            select = { selectedProject = it },
                            run = run,
                            create = create,
                            projects = { projectsFromSettings = false; destination = "projects" },
                            settings = { projectsFromSettings = false; destination = "settings" },
                            plan = plan,
                            capture = openCapture,
                            thoughts = { thoughtsProject = it; tab = 1; destination = null },
                            edit = { note = it },
                            platform = platform,
                            editorOpen = editorOpen,
                            dimEnabled = editors.dimEnabled,
                            setDimEnabled = { editors.dimEnabled = it },
                            execute = execute
                        )
                        1 -> ThoughtsScreen(snapshot, thoughtsProject, { thoughtsProject = it }, run, openCapture, { thought -> note = NoteRequest("Edit thought", thought.text, 500) { AppCommand.EditThought(thought.id, it) } })
                        else -> StatsScreen(snapshot, now, { sessionID = it }, { projectEditor = ProjectDraft.from(snapshot, it, now) })
                    }
                }
              }
            }
        }
        sessionID?.let { id -> SessionDetail(snapshot, id, { sessionID = null }, execute) { note = it } }
        note?.let { request -> key(request) { if (request.title in setOf("Session plan", "Next step")) PlanEditor(request.text, { note = null }, title = request.title) { execute(request.command(it)) } else TextEditor(request.title, request.text, request.limit, { note = null }) { execute(request.command(it)) } } }
        capture?.let { context -> key(context.id) { ThoughtComposer(snapshot, context, { capture = null }, execute) } }
        projectEditor?.let { draft -> key(draft.projectID) { ProjectEditor(draft, snapshot, now, { projectEditor = null }) { edited -> val result = execute(AppCommand.SaveProjectSettings(edited)); if (result == MutationResult.Success && edited.isNew) selectedProject = edited.projectID; result } } }
        (localError ?: error)?.let { message -> AlertDialog(onDismissRequest = { localError = null; onDismissError() }, title = { Text("Pomodoro") }, text = { Text(message) }, confirmButton = { TextButton({ localError = null; onDismissError() }) { Text("OK") } }) }
    }
}
