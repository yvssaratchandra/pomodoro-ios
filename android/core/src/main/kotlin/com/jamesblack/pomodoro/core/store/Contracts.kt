package com.jamesblack.pomodoro.core.store

import com.jamesblack.pomodoro.core.*
import kotlinx.serialization.Serializable

@Serializable enum class AlarmDisposition { pending, claimed, cancelled }
@Serializable data class AlarmTicket(val timerID: String, val deadline: Double, val sound: CompletionSound, val disposition: AlarmDisposition = AlarmDisposition.pending)
@Serializable data class LocalDocument(val version: Int = 1, val snapshot: AppSnapshot = AppSnapshot(), val alarmTickets: List<AlarmTicket> = emptyList())
interface SnapshotPersistence { suspend fun load(): LocalDocument?; suspend fun save(document: LocalDocument) }
fun interface StoreEffects {
    suspend fun synchronize(document: LocalDocument)
    suspend fun deliverCompletion(ticket: AlarmTicket, snapshot: AppSnapshot) {}
}
sealed interface LoadState {
    data object Loading : LoadState
    data class Ready(val snapshot: AppSnapshot) : LoadState
    data class Failed(val message: String) : LoadState
}
sealed interface MutationResult {
    data object Success : MutationResult
    data class Failure(val message: String) : MutationResult
}
data class PendingDeletion(val sessions: List<FocusSession> = emptyList(), val thoughts: List<CapturedThought> = emptyList(), val expiresAt: Double) { val count: Int get() = sessions.size + thoughts.size }
sealed interface AppCommand {
    data class StartFocus(val projectID: String, val minutes: Int) : AppCommand
    data object StartBreak : AppCommand
    data object SkipBreak : AppCommand
    data class SetBreakDuration(val offer: BreakOffer, val minutes: Int) : AppCommand
    data class RememberFocusDuration(val projectID: String, val minutes: Int) : AppCommand
    data object EndTimer : AppCommand
    data class DiscardFocus(val timerID: String) : AppCommand
    data object Reconcile : AppCommand
    data object Recover : AppCommand
    data class AlarmFired(val timerID: String, val deadline: Double) : AppCommand
    data class SaveProjectSettings(val draft: ProjectDraft) : AppCommand
    data class SetPendingPlan(val projectID: String, val text: String) : AppCommand
    data class EditIntention(val id: String, val active: Boolean, val text: String) : AppCommand
    data class SaveNextStep(val sessionID: String, val text: String, val promote: Boolean = false) : AppCommand
    data class CaptureThought(val context: ThoughtCaptureContext, val text: String) : AppCommand
    data class EditThought(val id: String, val text: String) : AppCommand
    data class SetThoughtsCompleted(val ids: Set<String>, val completed: Boolean) : AppCommand
    data class DeleteThoughts(val ids: Set<String>) : AppCommand
    data class DeleteSessions(val ids: Set<String>) : AppCommand
    data object UndoDeletion : AppCommand
    data object DismissUndo : AppCommand
    data object ExpireUndo : AppCommand
    data class MergeProjects(val source: String, val destination: String) : AppCommand
    data class DeleteEmptyProject(val id: String) : AppCommand
    data class UpdateSettings(val settings: Settings) : AppCommand
    data class SaveDailyGoals(val projectID: String, val minutes: List<Int>) : AppCommand
    data class SaveWeeklyGoal(val projectID: String, val minutes: Int?, val effectiveWeek: Double? = null) : AppCommand
    data class CancelScheduledWeeklyGoal(val projectID: String, val effectiveWeek: Double) : AppCommand
    data class AssignLegacyDailyGoal(val projectID: String, val replacingExisting: Boolean = false) : AppCommand
    data object DiscardLegacyDailyGoal : AppCommand
    data class Restore(val snapshot: AppSnapshot) : AppCommand
}
