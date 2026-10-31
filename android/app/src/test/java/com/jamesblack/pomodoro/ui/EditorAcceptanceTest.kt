package com.jamesblack.pomodoro.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class)
class EditorAcceptanceTest {
    @get:Rule val compose = createComposeRule()
    private class Platform : PlatformActions {
        override val notificationStatus = ""
        var imports = 0
        override fun requestNotifications() {}
        override fun testSound(kind: TimerKind) {}
        override fun openNotificationSettings() {}
        override fun exportBackup() {}
        override fun importBackup() { imports++ }
        override fun pinShortcut(route: AppRoute) {}
    }
    @Test fun projectSaveFailurePreservesEditorDraft() {
        val now = Time.now(); val initial = ProjectDraft.from(AppSnapshot(), now = now)
        var dismissed = false
        compose.setContent { PomodoroTheme(Appearance.light) { ProjectEditor(initial, AppSnapshot(), now, { dismissed = true }) { MutationResult.Failure("Disk full") } } }
        compose.onNodeWithText("Project name").performTextInput("Unsaved project")
        compose.onNodeWithText("Save", useUnmergedTree = true).performClick()
        compose.onNodeWithText("Disk full").assertIsDisplayed()
        compose.onNodeWithText("Unsaved project").assertIsDisplayed()
        assertFalse(dismissed)
        compose.onNodeWithText("Cancel").performClick()
        compose.onNodeWithText("Discard changes?").assertIsDisplayed()
        compose.onNodeWithText("Keep editing").performClick()
        compose.onNodeWithText("Unsaved project").assertIsDisplayed()
    }
    @Test fun failedThoughtSaveKeepsTextAndCapturedOrigin() {
        val project = Project(name = "Work")
        val timer = TimerEngine.startFocus(AppSnapshot(projects = listOf(project)), project.id, 10).activeTimer!!
        val context = ThoughtCaptureContext(project.id, timer.id)
        var received: AppCommand.CaptureThought? = null
        compose.setContent { PomodoroTheme(Appearance.light) { ThoughtComposer(AppSnapshot(projects = listOf(project)), context, {}) { command -> received = command as AppCommand.CaptureThought; MutationResult.Failure("Cannot save") } } }
        compose.onNodeWithText("Add a thought…").performTextInput("Keep this draft")
        compose.onNodeWithText("Add thought").performClick()
        compose.onNodeWithText("Cannot save").assertIsDisplayed()
        compose.onNodeWithText("Keep this draft").assertIsDisplayed()
        assertEquals(timer.id, received!!.context.originSessionID)
        assertEquals(project.id, received!!.context.projectID)
    }
    @Test fun restoreIsAvailableOnlyWhileIdle() {
        val platform = Platform()
        val project = Project(name = "Work")
        val running = TimerEngine.startFocus(AppSnapshot(projects = listOf(project)), project.id, 10)
        var state by androidx.compose.runtime.mutableStateOf(running)
        compose.setContent { PomodoroTheme(Appearance.light) { SettingsScreen(state, platform, {}, { MutationResult.Success }) } }
        compose.onNodeWithText("Restore backup").performScrollTo().assertIsNotEnabled()
        compose.runOnIdle { state = state.copy(activeTimer = null) }
        compose.onNodeWithText("Restore backup").assertIsEnabled().performClick()
        assertEquals(1, platform.imports)
    }
    @Test fun countdownNeverExceedsPlannedDurationBeforeNextClockTick() {
        val startedAt = Time.now()
        val project = Project(name = "Work")
        val running = TimerEngine.startFocus(AppSnapshot(projects = listOf(project)), project.id, 25, startedAt)
        compose.setContent { PomodoroUi(running, startedAt - 3, null, null, null, {}, { MutationResult.Success }, Platform()) }
        compose.onNodeWithText("25:00").assertIsDisplayed()
    }

}
