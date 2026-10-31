package com.jamesblack.pomodoro.ui

import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*

interface PlatformActions {
    val notificationStatus: String
    fun requestNotifications()
    fun testSound(kind: TimerKind)
    fun openNotificationSettings()
    fun exportBackup()
    fun importBackup()
    fun pinShortcut(route: AppRoute)
}
internal data class NoteRequest(val title: String, val text: String, val limit: Int = 280, val command: (String) -> AppCommand)
