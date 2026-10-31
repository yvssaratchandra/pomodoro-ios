package com.jamesblack.pomodoro.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.jamesblack.pomodoro.PomodoroApplication
import com.jamesblack.pomodoro.core.store.AppCommand
import kotlinx.coroutines.launch

class TimerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("timerID") ?: return
        val deadline = intent.getDoubleExtra("deadline", Double.NaN)
        if (!deadline.isFinite()) return
        val pending = goAsync()
        val app = context.applicationContext as PomodoroApplication
        app.scope.launch {
            try {
                app.store.initialize()
                app.store.execute(AppCommand.AlarmFired(id, deadline))
            } finally { pending.finish() }
        }
    }
}

class TimerRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED")) return
        val pending = goAsync()
        val app = context.applicationContext as PomodoroApplication
        app.scope.launch {
            try {
                app.store.initialize()
                app.store.execute(AppCommand.Recover)
            } finally { pending.finish() }
        }
    }
}
