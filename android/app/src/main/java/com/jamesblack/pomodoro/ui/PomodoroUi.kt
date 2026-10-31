package com.jamesblack.pomodoro.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import kotlinx.coroutines.launch
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun PomodoroUi(snapshot: AppSnapshot, now: Double, undo: PendingDeletion?, error: String?, route: AppRoute?, onRouteHandled: () -> Unit, execute: suspend (AppCommand) -> MutationResult, platform: PlatformActions, onDismissError: () -> Unit = {}) {
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var destination by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedProject by rememberSaveable { mutableStateOf<String?>(null) }
    var thoughtsProject by rememberSaveable { mutableStateOf<String?>(null) }
    var projectEditor by remember { mutableStateOf<ProjectDraft?>(null) }
    var note by remember { mutableStateOf<NoteRequest?>(null) }
    var capture by remember { mutableStateOf<ThoughtCaptureContext?>(null) }
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
            when (route) {
                AppRoute.Timer -> { tab = 0; destination = null }
                AppRoute.NewProject -> { tab = 0; destination = null; create() }
                is AppRoute.StartFocus -> { tab = 0; destination = null; val project = snapshot.projects.find { it.id == route.projectID }; if (snapshot.activeTimer == null && project?.status == ProjectStatus.ongoing) { selectedProject = project.id; execute(AppCommand.StartFocus(project.id, project.preferredFocusMinutes)) } }
                is AppRoute.CaptureThought -> {
                    val active = snapshot.activeTimer?.takeIf { it.kind == TimerKind.focus && (route.sessionID == null || it.id == route.sessionID) }
                    val saved = snapshot.sessions.find { it.id == route.sessionID }
                    openCapture(ThoughtCaptureContext(projectID = active?.projectID ?: saved?.projectID, originSessionID = active?.id ?: saved?.id))
                }
                is AppRoute.PlanNextSession -> plan(route.projectID)
            }
            onRouteHandled()
        } else if (route is AppRoute.CaptureThought && capture != null) {
            // Repeated capture links never replace a composer or its draft.
            onRouteHandled()
        }
    }
    PomodoroTheme(snapshot.settings.appearance) {
        Scaffold(topBar = { TopAppBar(title = { Text(destination?.replaceFirstChar { it.uppercase() } ?: listOf("Focus", "Thoughts", "Stats")[tab]) }, navigationIcon = { if (destination != null) IconButton({ destination = null }) { Icon(Icons.Outlined.ArrowBack, "Back") } }, actions = { if (destination == null && tab == 0) { IconButton({ destination = "settings" }) { Icon(Icons.Outlined.Settings, "Settings") }; IconButton({ destination = "projects" }) { Icon(Icons.Outlined.FolderOpen, "Projects") } } }) }, bottomBar = {
            Column {
                if (undo != null) Snackbar(action = { TextButton({ run(AppCommand.UndoDeletion) }) { Text("Undo") } }, dismissAction = { IconButton({ run(AppCommand.DismissUndo) }) { Icon(Icons.Outlined.Close, "Dismiss Undo") } }) { Text("${undo.count} ${if (undo.count == 1) "item" else "items"} deleted") }
                NavigationBar { listOf(Icons.Outlined.Timer, Icons.Outlined.CheckBox, Icons.Outlined.BarChart).forEachIndexed { index, icon -> NavigationBarItem(selected = tab == index && destination == null, onClick = { tab = index; destination = null }, icon = { Icon(icon, null) }, label = { Text(listOf("Focus", "Thoughts", "Stats")[index]) }) } }
            }
        }) { padding ->
            Box(Modifier.padding(padding)) {
                when (destination) {
                    "projects" -> ProjectsScreen(snapshot, now, run, { projectEditor = ProjectDraft.from(snapshot, it, now) }, create, { selectedProject = it; destination = null; tab = 0 }, { thoughtsProject = it; destination = null; tab = 1 }, { sessionID = it }, platform)
                    "settings" -> SettingsScreen(snapshot, platform, run)
                    else -> when (tab) {
                        0 -> FocusScreen(snapshot, now, selectedProject, { selectedProject = it }, run, create, { destination = "projects" }, plan, openCapture, { thoughtsProject = it; tab = 1 }, { note = it }, platform, editorOpen)
                        1 -> ThoughtsScreen(snapshot, thoughtsProject, { thoughtsProject = it }, run, openCapture, { thought -> note = NoteRequest("Edit thought", thought.text, 500) { AppCommand.EditThought(thought.id, it) } })
                        else -> StatsScreen(snapshot, now, { sessionID = it }, { projectEditor = ProjectDraft.from(snapshot, it, now) })
                    }
                }
            }
        }
        BackHandler(destination != null && !editorOpen) { destination = null }
        note?.let { request -> key(request) { TextEditor(request.title, request.text, request.limit, { note = null }) { execute(request.command(it)) } } }
        capture?.let { context -> key(context.id) { ThoughtComposer(snapshot, context, { capture = null }, execute) } }
        projectEditor?.let { draft -> key(draft.projectID) { ProjectEditor(draft, snapshot, now, { projectEditor = null }) { edited -> val result = execute(AppCommand.SaveProjectSettings(edited)); if (result == MutationResult.Success && edited.isNew) selectedProject = edited.projectID; result } } }
        sessionID?.let { id -> SessionDetail(snapshot, id, { sessionID = null }, execute) }
        (localError ?: error)?.let { message -> AlertDialog(onDismissRequest = { localError = null; onDismissError() }, title = { Text("Unable to save") }, text = { Text(message) }, confirmButton = { TextButton({ localError = null; onDismissError() }) { Text("OK") } }) }
    }
}
