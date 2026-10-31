package com.jamesblack.pomodoro.ui

import android.app.Application
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.jamesblack.pomodoro.core.Appearance
import com.jamesblack.pomodoro.core.store.MutationResult
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, qualifiers = "w393dp-h852dp-mdpi")
class PlanEditorAcceptanceTest {
    @get:Rule val compose = createComposeRule()

    @Test fun failedTaskSaveRetainsDraftAndAcceptedPlanUntilRetrySucceeds() {
        var fail = true
        var candidate = ""
        var dismissed = false
        compose.setContent {
            PomodoroTheme(Appearance.dark) {
                PlanEditor("Read notes", { dismissed = true }) {
                    candidate = it
                    if (fail) MutationResult.Failure("Cannot save plan") else MutationResult.Success
                }
            }
        }
        compose.onNodeWithText("Add a task").performTextInput("Write summary")
        compose.onNodeWithContentDescription("Add task").performClick()
        compose.onNodeWithText("Cannot save plan").assertIsDisplayed()
        compose.onNode(hasText("Read notes", substring = true)).assertIsDisplayed()
        compose.onNodeWithText("Write summary").assertIsDisplayed()
        assertTrue(candidate.contains("Read notes"))
        assertTrue(candidate.contains("Write summary"))
        compose.onNodeWithText("Done").performClick()
        compose.onNodeWithText("Discard unsaved task?").assertIsDisplayed()
        compose.onNodeWithText("Keep editing").performClick()
        assertFalse(dismissed)
        fail = false
        compose.onNodeWithContentDescription("Add task").performClick()
        compose.onNodeWithText("Cannot save plan").assertDoesNotExist()
        compose.onNode(hasText("Write summary", substring = true)).assertIsDisplayed()
        compose.onNodeWithText("Done").performClick()
        assertTrue(dismissed)
    }
}
