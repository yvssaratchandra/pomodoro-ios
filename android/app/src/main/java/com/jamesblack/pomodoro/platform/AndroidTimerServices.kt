package com.jamesblack.pomodoro.platform

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.jamesblack.pomodoro.MainActivity
import com.jamesblack.pomodoro.R
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*

class AndroidTimerServices(private val context: Context) : StoreEffects {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val scheduled = mutableSetOf<String>()
    private var testGeneration = 0

    fun notificationsAllowed(): Boolean = (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) && NotificationManagerCompat.from(context).areNotificationsEnabled()
    fun exactAlarmsAllowed(): Boolean = Build.VERSION.SDK_INT < 31 || alarmManager.canScheduleExactAlarms()
    fun status(): String = when {
        !notificationsAllowed() -> "Notifications are off. Enable them to receive completion alerts."
        !exactAlarmsAllowed() -> "Precise timer alerts are off. Allow alarms and reminders in system settings."
        else -> "Completion alerts follow your phone's notification volume, Do Not Disturb, and channel settings."
    }

    override suspend fun synchronize(document: LocalDocument) {
        val active = document.snapshot.activeTimer
        val pending = document.alarmTickets.filter { it.disposition == AlarmDisposition.pending }
        val future = pending.filter { it.timerID == active?.id && it.deadline > Time.now() }
        // A naturally completed pending alarm may already be queued for delivery.
        // Cancel only explicit cancellation/claims or records removed by a restore.
        (scheduled.filter { id -> pending.none { it.timerID == id } } + document.alarmTickets.filter { it.disposition != AlarmDisposition.pending }.map { it.timerID }).distinct().forEach(::cancel)
        future.forEach { ticket ->
            if (exactAlarmsAllowed()) {
                try {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, Time.toInstant(ticket.deadline).toEpochMilli(), alarmIntent(ticket.timerID, ticket.deadline))
                    scheduled += ticket.timerID
                } catch (_: SecurityException) { /* Permission can be revoked between check and scheduling. */ }
            }
        }
        if (active != null && active.deadline > Time.now() && notificationsAllowed()) showCountdown(document.snapshot, active)
        else notifications.cancel(COUNTDOWN)
    }

    override suspend fun deliverCompletion(ticket: AlarmTicket, snapshot: AppSnapshot) {
        if (!notificationsAllowed()) return
        val channel = soundChannel(ticket.sound, snapshot.settings.haptics)
        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Timer complete")
            .setContentText("Open Pomodoro when you're ready for the next session.")
            .setContentIntent(openIntent("pomodoro://timer", ticket.timerID))
            .setAutoCancel(true).setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
        notifications.notify(ticket.timerID, COMPLETION, builder.build())
    }

    fun testSound(sound: CompletionSound, haptics: Boolean = true): String {
        testGeneration++
        if (sound == CompletionSound.silent) { notifications.cancel(TEST); return "Sound is off." }
        if (!notificationsAllowed()) return "Notifications are off. Enable notifications to test an alert."
        val channelID = soundChannel(sound, haptics)
        val channel = notifications.getNotificationChannel(channelID)
        if (channel.importance == NotificationManager.IMPORTANCE_NONE || channel.sound == null) return "This alert channel is silent. Check notification settings."
        notifications.cancel(TEST)
        notifications.notify(TEST, NotificationCompat.Builder(context, channelID)
            .setSmallIcon(R.drawable.ic_notification).setContentTitle("Pomodoro test alert")
            .setContentText("Completion alerts use this notification sound.")
            .setAutoCancel(true).setTimeoutAfter(5000)
            .setContentIntent(openIntent("pomodoro://timer", "test-$testGeneration")).build())
        return "Test alert posted. Audible delivery depends on your phone's settings."
    }

    fun notificationSettingsIntent(): Intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)

    @androidx.annotation.RequiresApi(31)
    fun alarmSettingsIntent(): Intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))

    private fun showCountdown(snapshot: AppSnapshot, timer: ActiveTimer) {
        notifications.createNotificationChannel(NotificationChannel(COUNTDOWN_CHANNEL, "Running timer", NotificationManager.IMPORTANCE_LOW).apply {
            setSound(null, null); enableVibration(false); description = "Silent countdown for the current focus or break."
        })
        val name = if (snapshot.settings.showProjectNameOnLockScreen) snapshot.projects.find { it.id == timer.projectID }?.name else null
        val plan = if (snapshot.settings.showIntentionOnLockScreen) timer.intention else null
        val detail = listOfNotNull(name, plan).joinToString(" · ").take(240).ifEmpty { "Tap to open Pomodoro" }
        val public = NotificationCompat.Builder(context, COUNTDOWN_CHANNEL)
            .setSmallIcon(R.drawable.ic_notification).setContentTitle(timer.kind.title)
            .setContentText(detail).setWhen(Time.toInstant(timer.deadline).toEpochMilli())
            .setUsesChronometer(true).setChronometerCountDown(true).build()
        val builder = NotificationCompat.Builder(context, COUNTDOWN_CHANNEL)
            .setSmallIcon(R.drawable.ic_notification).setContentTitle(timer.kind.title).setContentText(detail)
            .setWhen(Time.toInstant(timer.deadline).toEpochMilli()).setUsesChronometer(true).setChronometerCountDown(true)
            .setOngoing(true).setOnlyAlertOnce(true).setSilent(true)
            .setTimeoutAfter(((timer.deadline - Time.now()) * 1000).toLong().coerceAtLeast(1))
            .setPublicVersion(public).setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openIntent("pomodoro://timer", "timer"))
        if (timer.kind == TimerKind.focus) builder.addAction(0, "Add thought", openIntent("pomodoro://thoughts/new?session=${timer.id}", "thought"))
        notifications.notify(COUNTDOWN, builder.build())
    }

    private fun soundChannel(sound: CompletionSound, haptics: Boolean): String {
        val channelID = "completion_${sound.name}_${if (haptics) "vibrate" else "quiet"}_v1"
        val uri = when (sound) {
            CompletionSound.systemDefault -> RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            CompletionSound.silent -> null
            else -> Uri.parse("android.resource://${context.packageName}/raw/${if (sound == CompletionSound.softTap) "soft_tap" else sound.name}")
        }
        notifications.createNotificationChannel(NotificationChannel(channelID, "Completion · ${sound.title}", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Completion and test alerts using ${sound.title}."
            setSound(uri, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            enableVibration(haptics)
            if (haptics) vibrationPattern = longArrayOf(0, 80)
        })
        return channelID
    }

    private fun alarmIntent(id: String, deadline: Double): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, TimerAlarmReceiver::class.java).setData(Uri.parse("pomodoro-internal://deadline/$id"))
            .putExtra("timerID", id).putExtra("deadline", deadline), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun cancel(id: String) { alarmManager.cancel(alarmIntent(id, 0.0)); scheduled -= id }
    private fun openIntent(uri: String, key: String): PendingIntent = PendingIntent.getActivity(context, key.hashCode(),
        Intent(context, MainActivity::class.java).setAction(Intent.ACTION_VIEW).setData(Uri.parse(uri))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    companion object {
        const val COUNTDOWN_CHANNEL = "running_timer_v1"
        const val COUNTDOWN = 100
        const val COMPLETION = 101
        const val TEST = 102
    }
}
