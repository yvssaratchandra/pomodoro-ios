package com.jamesblack.pomodoro.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*

@Composable
internal fun SettingsScreen(
    state: AppSnapshot,
    platform: PlatformActions,
    run: (AppCommand) -> Unit,
    execute: suspend (AppCommand) -> MutationResult,
    onExit: () -> Unit = {},
    openProjects: () -> Unit = {}
) {
    var page by rememberSaveable { mutableStateOf<String?>(null) }
    val pageTitles = mapOf(
        "timer" to "Timer defaults",
        "sounds" to "Sounds & haptics",
        "appearance" to "Appearance",
        "privacy" to "Lock Screen privacy",
        "shortcuts" to "Shortcuts",
        "backup" to "Backup & restore",
        "consistency" to "Consistency",
        "help" to "Help"
    )
    BackHandler(enabled = page != null) { page = null }

    key(page ?: "settings") {
        Page(horizontalPadding = 16.dp, verticalSpacing = 32.dp, header = {
            ScreenHeader(
                title = page?.let { pageTitles[it] ?: "Settings" } ?: "Settings",
                largeTitle = false,
                leading = {
                    TextButton(modifier = Modifier.semantics { contentDescription = "Back" }, onClick = { if (page == null) onExit() else page = null }, contentPadding = PaddingValues(0.dp)) {
                        Icon(Icons.Outlined.ChevronLeft, contentDescription = null, modifier = Modifier.size(24.dp))
                        Text(if (page == null) "Focus" else "Settings")
                    }
                }
            )
        }) {
            when (page) {
                null -> {
                    GroupedSection("") {
                        InsetGroupedRow("Projects", leadingIcon = Icons.Outlined.Folder, onClick = openProjects)
                    }
                    GroupedSection("PREFERENCES") {
                        InsetGroupedRow("Timer defaults", leadingIcon = Icons.Outlined.Timer, onClick = { page = "timer" })
                        SettingsSeparator()
                        InsetGroupedRow("Sounds & haptics", leadingIcon = Icons.Outlined.NotificationsNone, onClick = { page = "sounds" })
                        SettingsSeparator()
                        InsetGroupedRow("Appearance", leadingIcon = Icons.Outlined.Palette, onClick = { page = "appearance" })
                        SettingsSeparator()
                        InsetGroupedRow("Consistency", "${state.settings.consistencyTargetDays} days", leadingIcon = Icons.Outlined.CalendarMonth, onClick = { page = "consistency" })
                    }
                    GroupedSection("ACCESS") {
                        InsetGroupedRow("Shortcuts", leadingIcon = Icons.Outlined.GridView, onClick = { page = "shortcuts" })
                        SettingsSeparator()
                        InsetGroupedRow("Lock Screen privacy", leadingIcon = Icons.Outlined.Shield, onClick = { page = "privacy" })
                    }
                    GroupedSection("DATA & SUPPORT") {
                        InsetGroupedRow("Backup & restore", leadingIcon = Icons.Outlined.Storage, onClick = { page = "backup" })
                        SettingsSeparator()
                        InsetGroupedRow("Help", leadingIcon = Icons.AutoMirrored.Outlined.HelpOutline, onClick = { page = "help" })
                    }
                    Hint("All app data stays on this phone.")
                }
                "timer" -> TimerDefaultsSettings(state, run, execute)
                "sounds" -> SoundsSettings(state, platform, run)
                "appearance" -> AppearanceSettings(state, run)
                "privacy" -> PrivacySettings(state, run)
                "shortcuts" -> ShortcutsSettings(platform)
                "backup" -> BackupSettings(state, platform)
                "consistency" -> ConsistencySettings(state, run)
                else -> HelpSettings(platform)
            }
        }
    }
}

@Composable
private fun TimerDefaultsSettings(
    state: AppSnapshot,
    run: (AppCommand) -> Unit,
    execute: suspend (AppCommand) -> MutationResult
) {
    Section("New projects") {
        MinuteControl(
            "Focus",
            state.settings.defaultFocusMinutes,
            10,
            60,
            save = { execute(AppCommand.UpdateSettings(state.settings.copy(defaultFocusMinutes = it))) },
            onChange = {}
        )
        MinuteControl(
            "Short break",
            state.settings.defaultShortBreakMinutes,
            1,
            60,
            save = { execute(AppCommand.UpdateSettings(state.settings.copy(defaultShortBreakMinutes = it))) },
            onChange = {}
        )
        MinuteControl(
            "Long break",
            state.settings.defaultLongBreakMinutes,
            1,
            60,
            save = { execute(AppCommand.UpdateSettings(state.settings.copy(defaultLongBreakMinutes = it))) },
            onChange = {}
        )
    }
    Section("Break cycle") {
        ChoiceRow(
            label = "Long break after",
            selected = "${state.settings.longBreakInterval} focus sessions",
            options = (1..12).map { it.toString() to "$it focus sessions" },
            enabled = state.activeTimer == null,
            onSelect = { run(AppCommand.UpdateSettings(state.settings.copy(longBreakInterval = it.toInt()))) }
        )
        GroupedRow("Completed in cycle", "${state.completedInCycle}")
        if (state.activeTimer != null) Hint("End the running timer before changing the break cycle.")
        Hint("Breaks start manually. Pomodoro never starts the next phase automatically.")
    }
}

@Composable
private fun SoundsSettings(state: AppSnapshot, platform: PlatformActions, run: (AppCommand) -> Unit) {
    Section("Completion alerts") {
        SettingsToggle("Notification sounds", state.settings.notificationSound) {
            run(AppCommand.UpdateSettings(state.settings.copy(notificationSound = it)))
        }
        ChoiceRow(
            label = "Focus complete",
            selected = state.settings.focusCompletionSound.title,
            options = CompletionSound.entries.map { it.name to it.title },
            enabled = state.settings.notificationSound,
            onSelect = { run(AppCommand.UpdateSettings(state.settings.copy(focusCompletionSound = CompletionSound.valueOf(it)))) }
        )
        Action("Test focus completion alert", enabled = state.settings.notificationSound) { platform.testSound(TimerKind.focus) }
        ChoiceRow(
            label = "Break complete",
            selected = state.settings.breakCompletionSound.title,
            options = CompletionSound.entries.map { it.name to it.title },
            enabled = state.settings.notificationSound,
            onSelect = { run(AppCommand.UpdateSettings(state.settings.copy(breakCompletionSound = CompletionSound.valueOf(it)))) }
        )
        Action("Test break completion alert", enabled = state.settings.notificationSound) { platform.testSound(TimerKind.shortBreak) }
        SettingsToggle("Haptics", state.settings.haptics) {
            run(AppCommand.UpdateSettings(state.settings.copy(haptics = it)))
        }
        Hint("Completion sounds use Android notifications and your phone's notification volume. Notification channels and Do Not Disturb can silence them.")
    }
    Section("Notification status") {
        Hint(platform.notificationStatus.ifBlank { "Notification status is unavailable." })
        Action("Enable notifications") { platform.requestNotifications() }
        OutlinedButton(
            onClick = platform::openNotificationSettings,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
        ) { Text("Open notification settings") }
    }
}

@Composable
private fun AppearanceSettings(state: AppSnapshot, run: (AppCommand) -> Unit) {
    Section("Theme") {
        SegmentedSelector(
            options = Appearance.entries.map { it.name to it.title() },
            selected = state.settings.appearance.name,
            onSelect = { run(AppCommand.UpdateSettings(state.settings.copy(appearance = Appearance.valueOf(it)))) }
        )
    }
}

@Composable
private fun PrivacySettings(state: AppSnapshot, run: (AppCommand) -> Unit) {
    Section("Show on the Lock Screen") {
        SettingsToggle("Project name", state.settings.showProjectNameOnLockScreen) {
            run(AppCommand.UpdateSettings(state.settings.copy(showProjectNameOnLockScreen = it)))
        }
        SettingsToggle("Session plan", state.settings.showIntentionOnLockScreen) {
            run(AppCommand.UpdateSettings(state.settings.copy(showIntentionOnLockScreen = it)))
        }
        Hint("Thoughts and next steps stay inside the app.")
    }
}

@Composable
private fun ShortcutsSettings(platform: PlatformActions) {
    Section("Add a shortcut") {
        Action("Add thought shortcut") { platform.pinShortcut(AppRoute.CaptureThought()) }
        OutlinedButton(
            onClick = { platform.pinShortcut(AppRoute.Timer) },
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
        ) { Text("Add Focus shortcut") }
        Hint("Open a project to add its quick-start shortcut.")
    }
}

@Composable
private fun BackupSettings(state: AppSnapshot, platform: PlatformActions) {
    Section("JSON backup") {
        Action("Export backup") { platform.exportBackup() }
        Hint("Projects, saved sessions, thoughts, goals, and settings are included. An active timer is not exported.")
        OutlinedButton(
            onClick = platform::importBackup,
            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
            enabled = state.activeTimer == null
        ) { Text("Restore backup") }
        if (state.activeTimer != null) Hint("End your timer before restoring a backup.")
        Hint("Restoring replaces current data after confirmation. Backup files are limited to 50 MB.")
    }
}

@Composable
private fun ConsistencySettings(state: AppSnapshot, run: (AppCommand) -> Unit) {
    Section("Weekly focused-day target") {
        ChoiceRow(
            label = "Target",
            selected = "${state.settings.consistencyTargetDays} days",
            options = (1..7).map { it.toString() to "$it days" },
            onSelect = { run(AppCommand.UpdateSettings(state.settings.copy(consistencyTargetDays = it.toInt()))) }
        )
        Hint("A day counts after at least 10 minutes of actual focus. Rest days are not failures.")
    }
}

@Composable
private fun HelpSettings(platform: PlatformActions) {
    Section("Timers") {
        Hint("Choose or create a project and start a focus session. When focus finishes, start or skip your break. Sessions never start automatically.")
        Hint("End Focus saves elapsed work. Discard removes the running session. Thoughts remain saved separately, and statistics use saved focus only.")
    }
    Section("Sounds") {
        Hint("System Default uses Android's default notification sound. Sound follows the notification channel, phone volume, Do Not Disturb, and notification permission.")
        Hint(platform.notificationStatus.ifBlank { "Check Android notification settings if alerts are not available." })
    }
    Section("Your data") {
        Hint("App data stays on this phone. Pomodoro has no account, tracking, advertising, or automatic synchronization. Export a backup to transfer data.")
        Hint("Android may delay alarms after a force-stop or apply work-profile restrictions. Reopen Pomodoro after force-stopping it.")
    }
}

@Composable
private fun SettingsToggle(label: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = value, onCheckedChange = onChange)
    }
}

private fun Appearance.title(): String = name.replaceFirstChar(Char::uppercase)

@Composable
private fun SettingsSeparator() {
    HorizontalDivider(Modifier.padding(start = 64.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .55f))
}
