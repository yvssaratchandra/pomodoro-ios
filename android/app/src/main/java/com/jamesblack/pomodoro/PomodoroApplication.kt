package com.jamesblack.pomodoro

import android.app.Application
import android.content.Context
import android.os.SystemClock
import android.view.accessibility.AccessibilityManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.jamesblack.pomodoro.core.AppSnapshot
import com.jamesblack.pomodoro.core.store.AppCommand
import com.jamesblack.pomodoro.core.store.AppStore
import com.jamesblack.pomodoro.core.store.LoadState
import com.jamesblack.pomodoro.core.store.MutationResult
import com.jamesblack.pomodoro.platform.AndroidTimerServices
import com.jamesblack.pomodoro.platform.AtomicSnapshotPersistence
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.io.File

class PomodoroApplication : Application() {
    var foregroundRecovered = false
    var pendingRestore by mutableStateOf<AppSnapshot?>(null)
    var platformMessage by mutableStateOf<String?>(null)
    var exportReady by mutableStateOf(false)
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val timerServices by lazy { AndroidTimerServices(this) }
    val store by lazy {
        AppStore(
            persistence = AtomicSnapshotPersistence(File(noBackupFilesDir, "pomodoro.json")),
            uptime = { SystemClock.elapsedRealtime() / 1000.0 },
            accessibility = { (getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager).isTouchExplorationEnabled },
            effects = timerServices
        )
    }

    suspend fun initializeForeground() {
        store.initialize()
        if (!foregroundRecovered && store.state.value is LoadState.Ready) {
            foregroundRecovered = store.execute(AppCommand.Recover) == MutationResult.Success
        }
    }
}
