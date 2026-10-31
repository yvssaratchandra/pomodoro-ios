package com.jamesblack.pomodoro.ui

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, qualifiers = "w412dp-h915dp-mdpi")
class ThoughtsStatsAcceptanceTest {
    @get:Rule val compose = createComposeRule()
    private val now = 815140800.0
    private val project = Project(name = "Work")

    @Test fun thoughtFiltersResetAndBatchActionsUseVisibleItems() {
        val open = CapturedThought(projectID = project.id, createdAt = now - 60, text = "Prepare the review")
        val done = CapturedThought(projectID = project.id, createdAt = now - 120, text = "Send the agenda", completedAt = now - 30)
        val snapshot = AppSnapshot(projects = listOf(project), thoughts = listOf(open, done))
        var edited: CapturedThought? = null
        var command by mutableStateOf<AppCommand?>(null)
        compose.setContent {
            PomodoroTheme(Appearance.light) {
                ThoughtsScreen(snapshot, null, {}, { command = it }, {}, { edited = it })
            }
        }

        compose.onNodeWithText("Open").performClick()
        compose.onNodeWithText("Prepare the review").assertIsDisplayed()
        compose.onNodeWithText("Send the agenda").assertDoesNotExist()
        compose.onNodeWithText("Done").performClick()
        compose.onNodeWithText("Send the agenda").assertIsDisplayed()
        compose.onNodeWithText("Prepare the review").assertDoesNotExist()
        compose.onNodeWithText("All").performClick()
        compose.onNodeWithContentDescription("Search thoughts").performTextInput("Prepare")
        compose.onNodeWithText("Send the agenda").assertDoesNotExist()
        compose.onNodeWithText("Reset").performClick()
        compose.onNodeWithText("Prepare the review").assertIsDisplayed()
        compose.onNodeWithText("Send the agenda").assertIsDisplayed()
        compose.onNodeWithText("Prepare the review").performClick()
        assertEquals(open.id, edited?.id)

        compose.onNodeWithContentDescription("Thought actions").performClick()
        compose.onNodeWithText("Select thoughts").performClick()
        compose.onNodeWithContentDescription("Selection actions").performClick()
        compose.onNodeWithText("Select all visible").performClick()
        compose.onNodeWithContentDescription("Selection actions").performClick()
        compose.onNodeWithText("Mark done").performClick()
        val markDone = command as AppCommand.SetThoughtsCompleted
        assertEquals(setOf(open.id, done.id), markDone.ids)
        assertEquals(true, markDone.completed)
    }

    @Test fun swipeDeletionRequiresConfirmationAndTargetsOnlyThatThought() {
        val thought = CapturedThought(projectID = project.id, createdAt = now, text = "Review notes")
        var command: AppCommand? = null
        compose.setContent {
            PomodoroTheme(Appearance.dark) {
                ThoughtsScreen(AppSnapshot(projects = listOf(project), thoughts = listOf(thought)), null, {}, { command = it }, {}, {})
            }
        }
        compose.onNodeWithText("Review notes").performTouchInput { swipeLeft() }
        compose.onNodeWithText("Delete thought?").assertIsDisplayed()
        assertEquals(null, command)
        compose.onNodeWithText("Cancel").performClick()
        compose.onNodeWithText("Review notes").assertIsDisplayed()
        compose.onNodeWithText("Review notes").performTouchInput { longClick() }
        compose.onNodeWithText("Delete").performClick()
        compose.onNodeWithText("Delete").performClick()
        assertEquals(setOf(thought.id), (command as AppCommand.DeleteThoughts).ids)
    }

    @Test fun statsWeekShowsComparisonAndSessionHistoryAction() {
        val session = FocusSession(newID(), project.id, now - 1800, now - 900, 900, SessionOutcome.completed)
        val snapshot = AppSnapshot(projects = listOf(project), sessions = listOf(session))
        compose.setContent {
            PomodoroTheme(Appearance.light) {
                StatsScreen(snapshot, now, {}, {})
            }
        }

        compose.onNodeWithText("Week").performClick()
        val week = GoalEngine.week(now)
        val dateFormat = java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy")
        val dateRange = "${Time.date(week.start).format(dateFormat)} – ${Time.date(week.end - 1).format(dateFormat)}"
        compose.onNodeWithText(dateRange).assertIsDisplayed()
        compose.onNodeWithText("Details").performClick()
        compose.onNodeWithText("COMPARISON").assertIsDisplayed()
        compose.onNode(hasText("This period", substring = true)).assertIsDisplayed()
        compose.onNodeWithText("Done").performClick()
        compose.onNodeWithContentDescription("Previous week").performClick()
        compose.onNodeWithText("Return to current week").assertIsDisplayed()
    }
}
