package com.jamesblack.pomodoro.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*

@Composable internal fun SettingsScreen(state: AppSnapshot, platform: PlatformActions, run: (AppCommand) -> Unit) {
    var help by rememberSaveable { mutableStateOf(false) }
    Page {
        Section("Appearance") { SelectMenu("Theme", Appearance.entries.map { it.name to it.name.replaceFirstChar(Char::uppercase) }, state.settings.appearance.name) { run(AppCommand.UpdateSettings(state.settings.copy(appearance = Appearance.valueOf(it)))) } }
        Section("Completion alerts") {
            Toggle("Notification sounds", state.settings.notificationSound) { run(AppCommand.UpdateSettings(state.settings.copy(notificationSound = it))) }
            SelectMenu("Focus complete", CompletionSound.entries.map { it.name to it.title }, state.settings.focusCompletionSound.name) { run(AppCommand.UpdateSettings(state.settings.copy(focusCompletionSound = CompletionSound.valueOf(it)))) }
            TextButton({ platform.testSound(TimerKind.focus) }) { Text("Test focus completion alert") }
            SelectMenu("Break complete", CompletionSound.entries.map { it.name to it.title }, state.settings.breakCompletionSound.name) { run(AppCommand.UpdateSettings(state.settings.copy(breakCompletionSound = CompletionSound.valueOf(it)))) }
            TextButton({ platform.testSound(TimerKind.shortBreak) }) { Text("Test break completion alert") }
            Hint("Completion alerts use system notifications and your phone's notification volume. Android notification settings and Do Not Disturb can silence them. New choices apply to the next timer.")
            Hint(platform.notificationStatus)
            TextButton(platform::requestNotifications) { Text("Enable notifications") }
            TextButton(platform::openNotificationSettings) { Text("Open notification settings") }
        }
        Section("Lock screen privacy") {
            Toggle("Show project name", state.settings.showProjectNameOnLockScreen) { run(AppCommand.UpdateSettings(state.settings.copy(showProjectNameOnLockScreen = it))) }
            Toggle("Show session plan", state.settings.showIntentionOnLockScreen) { run(AppCommand.UpdateSettings(state.settings.copy(showIntentionOnLockScreen = it))) }
            Hint("Thoughts and next steps stay inside the app.")
        }
        Section("Timer defaults") {
            MinuteControl("Focus", state.settings.defaultFocusMinutes, 10, 60) { run(AppCommand.UpdateSettings(state.settings.copy(defaultFocusMinutes = it))) }
            MinuteControl("Short break", state.settings.defaultShortBreakMinutes, 1, 60) { run(AppCommand.UpdateSettings(state.settings.copy(defaultShortBreakMinutes = it))) }
            MinuteControl("Long break", state.settings.defaultLongBreakMinutes, 1, 60) { run(AppCommand.UpdateSettings(state.settings.copy(defaultLongBreakMinutes = it))) }
            SelectMenu("Long break after", (1..12).map { it.toString() to "$it focus sessions" }, state.settings.longBreakInterval.toString()) { run(AppCommand.UpdateSettings(state.settings.copy(longBreakInterval = it.toInt()))) }
        }
        Section("Consistency") { SelectMenu("Weekly focused-day target", (1..7).map { it.toString() to "$it days" }, state.settings.consistencyTargetDays.toString()) { run(AppCommand.UpdateSettings(state.settings.copy(consistencyTargetDays = it.toInt()))) }; Hint("At least 10 minutes of saved focus makes a focused day.") }
        Section("Backups") {
            Hint("Export projects, saved sessions, thoughts, goals, and settings as a JSON backup compatible with the iPhone app. An active timer is not exported.")
            TextButton(platform::exportBackup) { Text("Export backup") }
            TextButton(enabled = state.activeTimer == null, onClick = platform::importBackup) { Text("Restore backup") }
            if (state.activeTimer != null) Hint("End your timer before restoring a backup.")
            Hint("Restoring replaces current data after confirmation. Files stay in the location you choose.")
        }
        Section("Shortcuts") {
            TextButton({ platform.pinShortcut(AppRoute.CaptureThought()) }) { Text("Add thought shortcut") }
            TextButton({ platform.pinShortcut(AppRoute.Timer) }) { Text("Add Focus shortcut") }
            Hint("Open a project to add its quick-start shortcut.")
        }
        TextButton({ help = !help }) { Text("Help and privacy") }
        if (help) Section("Using Pomodoro") {
            Hint("Choose or create a project and start a focus session. When focus finishes, start or skip your break. Sessions never start automatically.")
            Hint("End Focus saves elapsed work; Discard removes the running session. Thoughts remain independently saved. Statistics include saved focus only.")
            Hint("Dim Focus keeps the display awake while its black surface is visible. Tap to reveal controls; the surface returns after five seconds.")
            Hint("All app data is stored on this phone. Pomodoro has no account, tracking, advertising, or automatic synchronization. Export a backup to transfer your data.")
            Hint("Android may prevent alarms after a force-stop, or your work profile may impose restrictions. Reopen Pomodoro after force-stopping it.")
        }
    }
}
@Composable private fun Toggle(label: String, value: Boolean, change: (Boolean) -> Unit) { Row(verticalAlignment = Alignment.CenterVertically) { Text(label, Modifier.weight(1f)); Switch(value, change) } }
