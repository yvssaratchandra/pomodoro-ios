package com.jamesblack.pomodoro.ui

import android.app.Application
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.core.graphics.Insets
import androidx.core.view.WindowInsetsCompat
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.MutationResult
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, qualifiers = "w393dp-h852dp-mdpi")
class EditorKeyboardAcceptanceTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test fun thoughtComposerKeepsHeaderAndInputAboveKeyboard() {
        val project = Project(name = "Work")
        compose.setContent {
            PomodoroTheme(Appearance.dark) {
                ThoughtComposer(AppSnapshot(projects = listOf(project)), ThoughtCaptureContext(project.id, "session"), {}) { MutationResult.Success }
            }
        }
        checkKeyboard("Session thoughts", "Add thought", "Add a thought…")
    }

    @Test fun planEditorKeepsHeaderAndInputAboveKeyboard() {
        compose.setContent { PomodoroTheme(Appearance.dark) { PlanEditor("Read notes", {}) { MutationResult.Success } } }
        checkKeyboard("Session plan", "Add task", "Add a task")
    }

    private fun checkKeyboard(title: String, send: String, input: String) {
        val before = compose.onNodeWithContentDescription(send).fetchSemanticsNode().boundsInRoot.bottom
        compose.runOnIdle {
            val window = requireNotNull(ShadowDialog.getLatestDialog().window)
            assertEquals(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING,
                window.attributes.softInputMode and WindowManager.LayoutParams.SOFT_INPUT_MASK_ADJUST)
            val insets = WindowInsetsCompat.Builder()
                .setInsets(WindowInsetsCompat.Type.ime(), Insets.of(0, 0, 0, 320))
                .setVisible(WindowInsetsCompat.Type.ime(), true).build()
            window.decorView.dispatchApplyWindowInsets(requireNotNull(insets.toWindowInsets()))
        }
        compose.waitForIdle()
        compose.onNodeWithText(title).assertIsDisplayed()
        compose.onNodeWithText("Done").assertIsDisplayed()
        compose.onNodeWithContentDescription(send).assertIsDisplayed()
        val after = compose.onNodeWithContentDescription(send).fetchSemanticsNode().boundsInRoot.bottom
        assertTrue("Input must move above the simulated keyboard: $before -> $after", after <= before - 300)
        compose.onNodeWithContentDescription(input).performTextInput("Draft survives keyboard")
        compose.onNodeWithText("Draft survives keyboard").assertIsDisplayed()
    }
}
