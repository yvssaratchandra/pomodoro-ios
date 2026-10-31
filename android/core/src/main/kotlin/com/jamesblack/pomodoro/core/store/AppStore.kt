package com.jamesblack.pomodoro.core.store

import com.jamesblack.pomodoro.core.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import java.time.ZoneId

/** The only writer of authoritative state. Effects observe only durable documents. */
class AppStore(private val persistence: SnapshotPersistence, private val now: () -> Double = Time::now, private val uptime: () -> Double = { System.nanoTime() / 1e9 }, private val zone: () -> ZoneId = ZoneId::systemDefault, private val accessibility: () -> Boolean = { false }, private val effects: StoreEffects = StoreEffects {}) {
    private val mutex = Mutex()
    private var document: LocalDocument? = null
    private val mutableState = MutableStateFlow<LoadState>(LoadState.Loading)
    val state: StateFlow<LoadState> = mutableState.asStateFlow()
    private val mutablePending = MutableStateFlow<PendingDeletion?>(null)
    val pendingDeletion: StateFlow<PendingDeletion?> = mutablePending.asStateFlow()
    private val mutableError = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = mutableError.asStateFlow()
    val snapshot: AppSnapshot get() = document?.snapshot ?: AppSnapshot()
    fun dismissError() { mutableError.value = null }

    suspend fun initialize() = withContext(NonCancellable) { mutex.withLock {
        if (document != null) return@withLock
        try {
            val loaded = persistence.load() ?: LocalDocument()
            require(loaded.version == 1) { "This app data requires a newer app version." }
            BackupCodec.validate(loaded.snapshot)
            val candidate = synchronizeTickets(loaded)
            persistence.save(candidate)
            publish(candidate)
            synchronize(candidate)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            mutableState.value = LoadState.Failed(e.message ?: "Unable to load saved data.")
        }
    } }

    suspend fun execute(command: AppCommand): MutationResult = withContext(NonCancellable) { mutex.withLock {
        val before = document ?: return@withLock failure("Saved data is not available.")
        expireUndo()
        if (command == AppCommand.DismissUndo || command == AppCommand.ExpireUndo) {
            if (command == AppCommand.DismissUndo) mutablePending.value = null
            return@withLock MutationResult.Success
        }
        try {
            val time = now()
            val original = before.snapshot
            var pendingAfter = mutablePending.value
            var tickets = before.alarmTickets
            var completion: AlarmTicket? = null
            val candidate = when (command) {
                is AppCommand.StartFocus -> TimerEngine.startFocus(original, command.projectID, command.minutes, time)
                AppCommand.StartBreak -> TimerEngine.startBreak(original, time)
                AppCommand.SkipBreak -> original.copy(breakOffer = null)
                is AppCommand.SetBreakDuration -> TimerEngine.setBreakDuration(original, command.offer, command.minutes)
                is AppCommand.RememberFocusDuration -> {
                    require(command.minutes in 10..60); project(original, command.projectID)
                    original.copy(projects = original.projects.map { if (it.id == command.projectID) it.copy(lastFocusMinutes = command.minutes) else it })
                }
                AppCommand.EndTimer -> { original.activeTimer?.let { timer -> tickets = tickets.map { if (it.timerID == timer.id) it.copy(disposition = AlarmDisposition.cancelled) else it } }; TimerEngine.finish(original, time, true) }
                is AppCommand.DiscardFocus -> { tickets = tickets.map { if (it.timerID == command.timerID) it.copy(disposition = AlarmDisposition.cancelled) else it }; TimerEngine.discardFocus(original, command.timerID) }
                AppCommand.Reconcile -> TimerEngine.finish(original, time)
                AppCommand.Recover -> {
                    tickets = tickets.map { if (it.deadline <= time && it.disposition == AlarmDisposition.pending) it.copy(disposition = AlarmDisposition.cancelled) else it }
                    TimerEngine.finish(original, time)
                }
                is AppCommand.AlarmFired -> {
                    val ticket = tickets.find { it.timerID == command.timerID && it.deadline == command.deadline }
                    if (ticket == null || ticket.disposition != AlarmDisposition.pending || time < ticket.deadline) return@withLock MutationResult.Success
                    // Claim before any external effect. Failure after this save may miss an alert,
                    // but a receiver retry cannot play it twice.
                    completion = ticket.copy(disposition = AlarmDisposition.claimed)
                    tickets = tickets.map { if (it == ticket) it.copy(disposition = AlarmDisposition.claimed) else it }
                    if (original.activeTimer?.id == ticket.timerID) TimerEngine.finish(original, time) else original
                }
                is AppCommand.SaveProjectSettings -> saveProjectDraft(original, command.draft, time, zone())
                is AppCommand.SetPendingPlan -> {
                    project(original, command.projectID)
                    val text = SessionText.normalize(command.text)
                    original.copy(projects = original.projects.map { if (it.id == command.projectID) it.copy(breadcrumb = text?.let { text -> ProjectBreadcrumb(text, time, it.breadcrumb?.originSessionID) }) else it })
                }
                is AppCommand.EditIntention -> {
                    val text = SessionText.normalize(command.text)
                    if (command.active) {
                        require(original.activeTimer?.id == command.id) { "This timer has already ended." }
                        original.copy(activeTimer = original.activeTimer?.copy(intention = text))
                    } else {
                        require(original.sessions.any { it.id == command.id }) { "This session is no longer available." }
                        original.copy(sessions = original.sessions.map { if (it.id == command.id) it.copy(intention = text) else it })
                    }
                }
                is AppCommand.SaveNextStep -> {
                    val session = requireNotNull(original.sessions.find { it.id == command.sessionID }) { "This session is no longer available." }
                    val p = project(original, session.projectID)
                    val text = SessionText.normalize(command.text)
                    require(!command.promote || p.breadcrumb == null || p.breadcrumb.text == text) { "This project already has a different plan for its next session." }
                    original.copy(sessions = original.sessions.map { if (it.id == session.id) it.copy(nextStep = text) else it }, projects = original.projects.map { if (command.promote && it.id == p.id) it.copy(breadcrumb = text?.let { value -> ProjectBreadcrumb(value, time, session.id) }) else it })
                }
                is AppCommand.CaptureThought -> ThoughtEngine.capture(original, command.context, command.text, time)
                is AppCommand.EditThought -> ThoughtEngine.edit(original, command.id, command.text)
                is AppCommand.SetThoughtsCompleted -> {
                    require(command.ids.isNotEmpty()) { "Select thoughts first." }
                    command.ids.fold(original) { state, id -> ThoughtEngine.setCompleted(state, id, command.completed, time) }
                }
                is AppCommand.DeleteThoughts -> {
                    val removed = original.thoughts.filter { it.id in command.ids }
                    require(removed.isNotEmpty() && removed.size == command.ids.size) { "These thoughts are no longer available." }
                    pendingAfter = deletion(pendingAfter, thoughts = removed)
                    original.copy(thoughts = original.thoughts.filterNot { it.id in command.ids })
                }
                is AppCommand.DeleteSessions -> {
                    val removed = original.sessions.filter { it.id in command.ids }
                    require(removed.isNotEmpty() && removed.size == command.ids.size) { "These sessions are no longer available." }
                    pendingAfter = deletion(pendingAfter, sessions = removed)
                    original.copy(sessions = original.sessions.filterNot { it.id in command.ids })
                }
                AppCommand.UndoDeletion -> {
                    val pending = requireNotNull(pendingAfter) { "There are no items to restore." }
                    val projectIDs = original.projects.map { it.id }.toSet()
                    require(pending.sessions.all { removed -> original.sessions.none { it.id == removed.id } && removed.projectID in projectIDs } && pending.thoughts.all { removed -> original.thoughts.none { it.id == removed.id } && (removed.projectID == null || removed.projectID in projectIDs) }) { "These items cannot be restored because their project or history has changed." }
                    pendingAfter = null
                    original.copy(sessions = original.sessions + pending.sessions, thoughts = original.thoughts + pending.thoughts)
                }
                is AppCommand.MergeProjects -> { pendingAfter = null; TimerEngine.merge(original, command.source, command.destination) }
                is AppCommand.DeleteEmptyProject -> {
                    require(canDeleteProject(command.id)) { "This project still has content. Put it on hold or merge it with another project." }
                    original.copy(projects = original.projects.filterNot { it.id == command.id }, goalPlan = original.goalPlan.copy(dailyProjectRevisions = original.goalPlan.dailyProjectRevisions.filterNot { it.projectID == command.id }, weeklyProjectRevisions = original.goalPlan.weeklyProjectRevisions.filterNot { it.projectID == command.id }))
                }
                is AppCommand.UpdateSettings -> {
                    val intervalChanged = command.settings.longBreakInterval != original.settings.longBreakInterval
                    require(!intervalChanged || original.activeTimer == null) { "End the timer before changing the break cycle." }
                    val timer = original.activeTimer?.copy(completionSound = command.settings.completionSound(original.activeTimer.kind))
                    if (timer != null) tickets = tickets.map { if (it.timerID == timer.id && it.disposition == AlarmDisposition.pending) it.copy(sound = timer.completionSound) else it }
                    original.copy(settings = command.settings, activeTimer = timer, completedInCycle = if (intervalChanged) 0 else original.completedInCycle)
                }
                is AppCommand.SaveDailyGoals -> { project(original, command.projectID); original.copy(goalPlan = GoalEngine.setDaily(original.goalPlan, command.projectID, command.minutes, time, zone())) }
                is AppCommand.SaveWeeklyGoal -> { project(original, command.projectID); original.copy(goalPlan = GoalEngine.setWeekly(original.goalPlan, command.projectID, command.minutes, time, zone(), command.effectiveWeek)) }
                is AppCommand.CancelScheduledWeeklyGoal -> {
                    project(original, command.projectID)
                    val day = LocalDay.at(GoalEngine.week(command.effectiveWeek, zone()).start, zone())
                    require(day > LocalDay.at(GoalEngine.week(time, zone()).start, zone())) { "Only future targets can be cancelled." }
                    original.copy(goalPlan = original.goalPlan.copy(weeklyProjectRevisions = original.goalPlan.weeklyProjectRevisions.filterNot { it.projectID == command.projectID && it.effectiveFrom == day }))
                }
                is AppCommand.AssignLegacyDailyGoal -> {
                    project(original, command.projectID)
                    val schedule = requireNotNull(original.goalPlan.pendingLegacyDailySchedule) { "There is no previous daily goal to assign." }
                    require(command.replacingExisting || GoalEngine.dailyTarget(command.projectID, time, original.goalPlan, zone()) == null) { "This project already has a daily goal." }
                    original.copy(goalPlan = GoalEngine.setDaily(original.goalPlan, command.projectID, schedule, time, zone()).copy(pendingLegacyDailySchedule = null))
                }
                AppCommand.DiscardLegacyDailyGoal -> original.copy(goalPlan = original.goalPlan.copy(pendingLegacyDailySchedule = null))
                is AppCommand.Restore -> {
                    require(original.activeTimer == null) { "End the timer before restoring a backup." }
                    require(command.snapshot.activeTimer == null) { "A backup cannot contain an active timer." }
                    tickets = emptyList(); pendingAfter = null; command.snapshot
                }
                AppCommand.DismissUndo, AppCommand.ExpireUndo -> original
            }
            BackupCodec.validate(candidate)
            val next = synchronizeTickets(before.copy(snapshot = candidate, alarmTickets = tickets))
            if (next != before) persistence.save(next)
            publish(next)
            mutablePending.value = pendingAfter
            mutableError.value = null
            synchronize(next)
            completion?.let { ticket ->
                try { effects.deliverCompletion(ticket, next.snapshot) }
                catch (e: Exception) { if (e is CancellationException) throw e; mutableError.value = "Saved completion, but Android could not deliver its alert: ${e.message ?: "delivery failed"}" }
            }
            MutationResult.Success
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            failure(e.message ?: "Unable to save changes.")
        }
    } }

    fun canDeleteProject(id: String): Boolean {
        val state = snapshot
        val pending = mutablePending.value?.takeIf { uptime() < it.expiresAt }
        return state.projects.any { it.id == id && it.breadcrumb == null } && state.sessions.none { it.projectID == id } && state.thoughts.none { it.projectID == id } && state.activeTimer?.projectID != id && state.breakOffer?.projectID != id && pending?.sessions?.any { it.projectID == id } != true && pending?.thoughts?.any { it.projectID == id } != true
    }
    private fun project(state: AppSnapshot, id: String): Project = requireNotNull(state.projects.find { it.id == id }) { "Project unavailable." }
    private fun expireUndo() { if (mutablePending.value?.let { uptime() >= it.expiresAt } == true) mutablePending.value = null }
    private fun deletion(previous: PendingDeletion?, sessions: List<FocusSession> = emptyList(), thoughts: List<CapturedThought> = emptyList()): PendingDeletion = PendingDeletion((previous?.sessions ?: emptyList()) + sessions, (previous?.thoughts ?: emptyList()) + thoughts, uptime() + if (accessibility()) 30 else 10)
    private fun publish(next: LocalDocument) { document = next; mutableState.value = LoadState.Ready(next.snapshot) }
    private fun synchronizeTickets(next: LocalDocument): LocalDocument {
        val timer = next.snapshot.activeTimer
        var tickets = next.alarmTickets
        if (timer != null && tickets.none { it.timerID == timer.id }) tickets = tickets + AlarmTicket(timer.id, timer.deadline, timer.completionSound)
        // Preserve a naturally completed pending ticket for the receiver. Explicit end/discard
        // cancels it in the command branch before entering this helper.
        return next.copy(alarmTickets = tickets.takeLast(64))
    }
    private suspend fun synchronize(next: LocalDocument) {
        try { effects.synchronize(next) } catch (e: Exception) { if (e is CancellationException) throw e; mutableError.value = "Saved changes, but Android integration failed: ${e.message ?: "please reopen the app to retry"}" }
    }
    private fun failure(message: String): MutationResult.Failure { mutableError.value = message; return MutationResult.Failure(message) }
}
