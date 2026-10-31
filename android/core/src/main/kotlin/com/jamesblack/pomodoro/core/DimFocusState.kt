package com.jamesblack.pomodoro.core

/** Presentation-only; uses monotonic uptime and never changes the persisted timer. */
data class DimFocusState(
    val sessionID: String? = null,
    val isDimmed: Boolean = false,
    val generation: Long = 0,
    val returnDeadline: Double? = null,
    val blockers: Set<String> = emptySet(),
    val interactionCount: Int = 0,
    private val eligibleSessionID: String? = null,
    private val focusVisible: Boolean = false,
    private val sceneActive: Boolean = false,
    private val accessibilityActive: Boolean = false,
) {
    val isEnabled: Boolean get() = sessionID != null
    val canPresent: Boolean get() = isEnabled && eligibleSessionID == sessionID && focusVisible && sceneActive && blockers.isEmpty() && interactionCount == 0
    val shouldKeepAwake: Boolean get() = isDimmed && canPresent
    private fun invalidateReturn() = copy(generation = generation + 1, returnDeadline = null)
    private fun resetReturn(uptime: Double): DimFocusState { val invalidated = invalidateReturn(); return if (invalidated.canPresent && !invalidated.isDimmed && !invalidated.accessibilityActive) invalidated.copy(returnDeadline = uptime + revealDuration) else invalidated }
    fun update(sessionID: String?, focusVisible: Boolean, sceneActive: Boolean, accessibilityActive: Boolean, uptime: Double): DimFocusState {
        if (eligibleSessionID == sessionID && this.focusVisible == focusVisible && this.sceneActive == sceneActive && this.accessibilityActive == accessibilityActive) return this
        val updated = copy(eligibleSessionID = sessionID, focusVisible = focusVisible, sceneActive = sceneActive, accessibilityActive = accessibilityActive)
        if (this.sessionID != null && this.sessionID != sessionID) return updated.disable()
        return updated.copy(isDimmed = false).resetReturn(uptime)
    }
    fun enable(uptime: Double): DimFocusState { val eligible = eligibleSessionID ?: return this; val enabled = copy(sessionID = eligible, interactionCount = 0).invalidateReturn(); return enabled.copy(isDimmed = enabled.canPresent).let { if (it.isDimmed) it else it.resetReturn(uptime) } }
    fun disable(): DimFocusState = copy(sessionID = null, isDimmed = false).invalidateReturn()
    fun reveal(uptime: Double): DimFocusState = copy(isDimmed = false).resetReturn(uptime)
    fun setBlocked(key: String, blocked: Boolean, uptime: Double): DimFocusState { val values = if (blocked) blockers + key else blockers - key; return if (values == blockers) this else copy(blockers = values, isDimmed = false).resetReturn(uptime) }
    fun beginInteraction(uptime: Double): DimFocusState = copy(interactionCount = interactionCount + 1, isDimmed = false).resetReturn(uptime)
    fun endInteraction(uptime: Double): DimFocusState = copy(interactionCount = maxOf(0, interactionCount - 1)).resetReturn(uptime)
    fun returnToDim(sessionID: String, generation: Long, uptime: Double): DimFocusState = if (this.sessionID == sessionID && this.generation == generation && canPresent && !accessibilityActive && returnDeadline != null && uptime >= returnDeadline) copy(isDimmed = true).invalidateReturn() else this
    companion object { const val revealDuration = 10.0 }
}
