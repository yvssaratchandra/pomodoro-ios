package com.jamesblack.pomodoro

import android.Manifest
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import com.jamesblack.pomodoro.ui.PlatformActions
import com.jamesblack.pomodoro.ui.PomodoroUi
import kotlinx.coroutines.*

class MainActivity : ComponentActivity() {
    private val app get() = application as PomodoroApplication
    private val routes = mutableStateListOf<AppRoute>()
    private var platformMessage: String?
        get() = app.platformMessage
        set(value) { app.platformMessage = value }
    private var notificationStatus by mutableStateOf("")
    private var pendingRestore: AppSnapshot?
        get() = app.pendingRestore
        set(value) { app.pendingRestore = value }
    private val exportFile get() = java.io.File(noBackupFilesDir, "pending-export.json")
    private var currentTime by mutableDoubleStateOf(Time.now())

    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        notificationStatus = app.timerServices.status()
        app.scope.launch { app.store.execute(AppCommand.Reconcile) }
    }
    private val createDocument = registerForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri == null) { exportFile.delete(); return@registerForActivityResult }
        app.scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    require(exportFile.exists()) { "The export was interrupted. Export the backup again." }
                    exportFile.inputStream().use { input -> requireNotNull(contentResolver.openOutputStream(uri, "wt")).use { input.copyTo(it) } }
                }
                platformMessage = "Backup exported."
            } catch (error: Exception) { platformMessage = "Unable to export backup: ${error.message}" }
            finally { exportFile.delete() }
        }
    }
    private val openDocument = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) app.scope.launch {
            try {
                val decoded = withContext(Dispatchers.IO) {
                    requireNotNull(contentResolver.openInputStream(uri)).use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            require(output.size() + count <= BackupCodec.maximumBytes) { "The backup exceeds the 50 MB limit." }
                            output.write(buffer, 0, count)
                        }
                        BackupCodec.decode(output.toByteArray())
                    }
                }
                pendingRestore = decoded
            } catch (error: Exception) { platformMessage = "Unable to read backup: ${error.message}" }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null) acceptIntent(intent)
        else savedInstanceState.getStringArrayList("pendingRoutes")?.forEach { AppRouter.parse(it)?.let(routes::add) }
        app.scope.launch { app.initializeForeground() }
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                notificationStatus = app.timerServices.status()
                while (isActive) {
                    currentTime = Time.now()
                    if (app.store.state.value is LoadState.Ready) {
                        app.store.snapshot.activeTimer?.takeIf { it.deadline <= currentTime }?.let { app.store.execute(AppCommand.Reconcile) }
                        app.store.execute(AppCommand.ExpireUndo)
                    }
                    delay(1000)
                }
            }
        }
        setContent {
            val state by app.store.state.collectAsStateWithLifecycle()
            val undo by app.store.pendingDeletion.collectAsStateWithLifecycle()
            val error by app.store.errorMessage.collectAsStateWithLifecycle()
            val lifecycle by lifecycle.currentStateFlow.collectAsState()
            LaunchedEffect(app.exportReady, lifecycle) {
                if (app.exportReady && lifecycle.isAtLeast(Lifecycle.State.RESUMED)) {
                    app.exportReady = false
                    createDocument.launch("Pomodoro-Backup.json")
                }
            }
            when (val loaded = state) {
                LoadState.Loading -> MaterialTheme { Surface(Modifier.fillMaxSize()) { Box(Modifier.padding(24.dp)) { CircularProgressIndicator() } } }
                is LoadState.Failed -> MaterialTheme { Surface(Modifier.fillMaxSize()) {
                    Column(Modifier.safeDrawingPadding().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text("Unable to open data", style = MaterialTheme.typography.headlineMedium)
                        Text("Your stored data has not been replaced. ${loaded.message}")
                        Button(onClick = { app.scope.launch { app.initializeForeground() } }) { Text("Retry") }
                    }
                } }
                is LoadState.Ready -> {
                    PomodoroUi(snapshot = loaded.snapshot, now = currentTime, undo = undo,
                        error = platformMessage ?: error, route = routes.firstOrNull(),
                        onRouteHandled = { if (routes.isNotEmpty()) routes.removeAt(0) },
                        onDismissError = { platformMessage = null; app.store.dismissError() },
                        execute = { command ->
                            if (command is AppCommand.StartFocus || command == AppCommand.StartBreak) requestNotifications()
                            app.scope.async { app.store.execute(command) }.await()
                        }, platform = platformActions)
                    pendingRestore?.let { imported -> com.jamesblack.pomodoro.ui.PomodoroTheme(loaded.snapshot.settings.appearance) {
                        AlertDialog(onDismissRequest = { pendingRestore = null }, title = { Text("Replace all app data?") },
                            text = { Text("Restore ${imported.projects.size} projects, ${imported.sessions.size} sessions, and ${imported.thoughts.size} thoughts. Current data will be replaced.") },
                            confirmButton = { TextButton(onClick = { app.scope.launch {
                                if (app.store.execute(AppCommand.Restore(imported)) == MutationResult.Success) {
                                    pendingRestore = null
                                    platformMessage = "Backup restored."
                                }
                            } }) { Text("Replace with backup") } },
                            dismissButton = { TextButton(onClick = { pendingRestore = null }) { Text("Cancel") } })
                    } }
                }
            }
        }
    }

    private val platformActions = object : PlatformActions {
        override val notificationStatus: String get() = this@MainActivity.notificationStatus
        override fun requestNotifications() = this@MainActivity.requestNotifications()
        override fun testSound(kind: TimerKind) {
            if (!app.timerServices.notificationsAllowed()) { requestNotifications(); platformMessage = "Enable notifications, then tap Test completion alert again."; return }
            platformMessage = app.timerServices.testSound(app.store.snapshot.settings.completionSound(kind), app.store.snapshot.settings.haptics)
        }
        override fun openNotificationSettings() { launchSettings(app.timerServices.notificationSettingsIntent()) }
        override fun exportBackup() {
            app.scope.launch {
                try {
                    val snapshot = app.store.snapshot
                    withContext(Dispatchers.IO) { exportFile.writeBytes(BackupCodec.encodeSaved(snapshot)) }
                    app.exportReady = true
                } catch (error: Exception) { platformMessage = "Unable to export backup: ${error.message}" }
            }
        }
        override fun importBackup() {
            if (app.store.snapshot.activeTimer != null) platformMessage = "End the timer before restoring a backup."
            else openDocument.launch(arrayOf("application/json", "application/octet-stream"))
        }
        override fun pinShortcut(route: AppRoute) {
            val manager = getSystemService(ShortcutManager::class.java)
            if (!manager.isRequestPinShortcutSupported) { platformMessage = "This launcher does not allow pinned shortcuts."; return }
            val title = when (route) {
                is AppRoute.StartFocus -> app.store.snapshot.projects.find { it.id == route.projectID }?.name ?: "Start focus"
                is AppRoute.CaptureThought -> "Add thought"
                else -> "Pomodoro"
            }
            val shortcut = ShortcutInfo.Builder(this@MainActivity, AppRouter.url(route)).setShortLabel(title.take(30))
                .setIcon(Icon.createWithResource(this@MainActivity, R.mipmap.ic_launcher))
                .setIntent(Intent(this@MainActivity, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(Uri.parse(AppRouter.url(route)))).build()
            try {
                if (!manager.requestPinShortcut(shortcut, null)) platformMessage = "The launcher did not accept the shortcut request."
            } catch (error: Exception) { platformMessage = "Unable to create shortcut: ${error.message}" }
        }
    }

    private fun requestNotifications() {
        if (Build.VERSION.SDK_INT >= 33 && !app.timerServices.notificationsAllowed()) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else if (Build.VERSION.SDK_INT in 31..32 && !app.timerServices.exactAlarmsAllowed()) launchSettings(app.timerServices.alarmSettingsIntent())
        notificationStatus = app.timerServices.status()
    }
    private fun launchSettings(intent: Intent) { try { startActivity(intent) } catch (_: Exception) { platformMessage = "Open your phone's app settings for Pomodoro." } }
    private fun acceptIntent(intent: Intent?) {
        val uri = intent?.dataString ?: return
        val parsed = AppRouter.parse(uri)
        if (parsed == null) platformMessage = "This Pomodoro link is not supported."
        else if (routes.lastOrNull() != parsed) routes.add(parsed)
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); acceptIntent(intent) }
    override fun onResume() {
        super.onResume()
        notificationStatus = app.timerServices.status()
        if (app.foregroundRecovered) app.scope.launch { app.store.execute(AppCommand.Reconcile) }
    }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putStringArrayList("pendingRoutes", ArrayList(routes.map(AppRouter::url)))
        super.onSaveInstanceState(outState)
    }
}
