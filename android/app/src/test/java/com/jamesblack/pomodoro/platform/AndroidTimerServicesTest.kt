package com.jamesblack.pomodoro.platform

import android.Manifest
import android.app.*
import android.content.Context
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, manifest = Config.NONE)
class AndroidTimerServicesTest {
    private lateinit var context: Context
    private lateinit var service: AndroidTimerServices
    private lateinit var notifications: NotificationManager
    private lateinit var alarms: AlarmManager
    @Before fun setup() {
        context = RuntimeEnvironment.getApplication()
        shadowOf(context as Application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        notifications = context.getSystemService(NotificationManager::class.java)
        alarms = context.getSystemService(AlarmManager::class.java)
        org.robolectric.shadows.ShadowAlarmManager.setCanScheduleExactAlarms(true)
        service = AndroidTimerServices(context)
    }
    private fun running(): LocalDocument {
        val project = Project(name = "Private project")
        val snapshot = TimerEngine.startFocus(AppSnapshot(projects = listOf(project)), project.id, 10, Time.now())
        val timer = snapshot.activeTimer!!
        return LocalDocument(snapshot = snapshot, alarmTickets = listOf(AlarmTicket(timer.id, timer.deadline, timer.completionSound)))
    }
    @Test fun schedulesExactAlarmAndSilentPrivateCountdownThenCancelsBoth() = runTest {
        val document = running(); service.synchronize(document)
        assertEquals(1, shadowOf(alarms).scheduledAlarms.size)
        val channel = notifications.getNotificationChannel(AndroidTimerServices.COUNTDOWN_CHANNEL)
        assertNull(channel.sound); assertEquals(NotificationManager.IMPORTANCE_LOW, channel.importance)
        val countdown = shadowOf(notifications).getNotification(AndroidTimerServices.COUNTDOWN)
        assertEquals("Tap to open Pomodoro", countdown.extras.getCharSequence(Notification.EXTRA_TEXT))
        assertEquals("Tap to open Pomodoro", countdown.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT))
        service.synchronize(document.copy(snapshot = document.snapshot.copy(activeTimer = null), alarmTickets = document.alarmTickets.map { it.copy(disposition = AlarmDisposition.cancelled) }))
        assertTrue(shadowOf(alarms).scheduledAlarms.isEmpty())
        assertNull(shadowOf(notifications).getNotification(AndroidTimerServices.COUNTDOWN))
    }
    @Test fun expiredTimerDoesNotRescheduleOrPostCountdown() = runTest {
        val document = running(); val timer = document.snapshot.activeTimer!!
        val past = timer.copy(startedAt = Time.now() - 1000)
        service.synchronize(document.copy(snapshot = document.snapshot.copy(activeTimer = past), alarmTickets = listOf(AlarmTicket(past.id, past.deadline, past.completionSound))))
        assertTrue(shadowOf(alarms).scheduledAlarms.isEmpty())
        assertNull(shadowOf(notifications).getNotification(AndroidTimerServices.COUNTDOWN))
    }
    @Test fun notificationDenialDoesNotPreventAlarmAndProducesHonestStatus() = runTest {
        shadowOf(context as Application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        service.synchronize(running())
        assertEquals(1, shadowOf(alarms).scheduledAlarms.size)
        assertNull(shadowOf(notifications).getNotification(AndroidTimerServices.COUNTDOWN))
        assertTrue(service.status().contains("Notifications are off"))
        assertTrue(service.testSound(CompletionSound.bell).contains("Notifications are off"))
    }
    @Test fun exactAlarmDenialDoesNotClaimSchedulingSucceeded() = runTest {
        org.robolectric.shadows.ShadowAlarmManager.setCanScheduleExactAlarms(false)
        service.synchronize(running())
        assertTrue(shadowOf(alarms).scheduledAlarms.isEmpty())
        assertTrue(service.status().contains("Precise timer alerts are off"))
    }
    @Test fun completionUsesStableSoundChannelAndHonorsSilence() = runTest {
        val document = running(); val ticket = document.alarmTickets.single().copy(sound = CompletionSound.bell, disposition = AlarmDisposition.claimed)
        service.deliverCompletion(ticket, document.snapshot)
        val bell = notifications.getNotificationChannel("completion_bell_vibrate_v1")
        assertEquals("android.resource://${context.packageName}/raw/bell", bell.sound.toString())
        assertNotNull(shadowOf(notifications).getNotification(ticket.timerID, AndroidTimerServices.COMPLETION))
        service.deliverCompletion(ticket.copy(sound = CompletionSound.silent), document.snapshot)
        assertNull(notifications.getNotificationChannel("completion_silent_vibrate_v1").sound)
        assertEquals("Sound is off.", service.testSound(CompletionSound.silent))
    }
    @Test fun naturallyFinishedPendingAlarmRemainsScheduledUntilReceiverClaimsIt() = runTest {
        val document = running(); service.synchronize(document)
        assertEquals(1, shadowOf(alarms).scheduledAlarms.size)
        val completed = document.copy(snapshot = document.snapshot.copy(activeTimer = null))
        service.synchronize(completed)
        assertEquals(1, shadowOf(alarms).scheduledAlarms.size)
        assertNull(shadowOf(notifications).getNotification(AndroidTimerServices.COUNTDOWN))
        service.synchronize(completed.copy(alarmTickets = completed.alarmTickets.map { it.copy(disposition = AlarmDisposition.claimed) }))
        assertTrue(shadowOf(alarms).scheduledAlarms.isEmpty())
    }

    @Test fun hapticPreferenceUsesIndependentChannelWithoutOverwritingExistingChoice() = runTest {
        val document = running(); val ticket = document.alarmTickets.single().copy(sound = CompletionSound.chime)
        service.deliverCompletion(ticket, document.snapshot)
        val vibrating = notifications.getNotificationChannel("completion_chime_vibrate_v1")
        assertTrue(vibrating.shouldVibrate())
        service.deliverCompletion(ticket, document.snapshot.copy(settings = document.snapshot.settings.copy(haptics = false)))
        val quiet = notifications.getNotificationChannel("completion_chime_quiet_v1")
        assertFalse(quiet.shouldVibrate()); assertTrue(vibrating.shouldVibrate())
        assertEquals(vibrating.sound, quiet.sound)
    }

}
