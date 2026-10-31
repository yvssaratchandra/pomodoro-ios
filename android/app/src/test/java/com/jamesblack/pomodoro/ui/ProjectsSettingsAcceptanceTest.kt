package com.jamesblack.pomodoro.ui

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.junit4.createComposeRule
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class)
class ProjectsSettingsAcceptanceTest {
    @get:Rule val compose = createComposeRule()

    private class Platform : PlatformActions {
        override val notificationStatus = "Notifications are enabled for Pomodoro."
        override fun requestNotifications() {}
        override fun testSound(kind: TimerKind) {}
        override fun openNotificationSettings() {}
        override fun exportBackup() {}
        override fun importBackup() {}
        override fun pinShortcut(route: AppRoute) {}
    }

    @Test fun projectDraftSurvivesNestedBackAndFailedSave() {
        val now = Time.now()
        val project = Project(name = "Work")
        val state = AppSnapshot(projects = listOf(project))
        val initial = ProjectDraft.from(state, project.id, now)
        var saved: ProjectDraft? = null
        var dismissed = false

        compose.setContent {
            PomodoroTheme(Appearance.light) {
                ProjectEditor(initial, state, now, { dismissed = true }) { draft ->
                    saved = draft
                    MutationResult.Failure("Disk full")
                }
            }
        }

        compose.onNodeWithText("Project name").performTextReplacement("Draft project")
        compose.onNodeWithText("Daily and weekly goals").performScrollTo().performClick()
        compose.onNodeWithText("Daily goal").performScrollTo().performClick()
        compose.onNodeWithText("Set daily goals").performScrollTo().performClick()
        compose.onNodeWithText("Monday · 60 min").performScrollTo().performClick()
        compose.onNodeWithText("Minutes (0–1440)").performTextReplacement("0")
        compose.onNodeWithText("Done").performClick()

        compose.onNodeWithText("Save", useUnmergedTree = true).performClick()
        compose.onNodeWithText("Disk full").assertIsDisplayed()
        compose.onNodeWithText("Monday · 0 min").performScrollTo().assertIsDisplayed()
        assertEquals("Draft project", saved?.name)
        assertEquals(0, saved?.dailySchedule?.firstOrNull() ?: -1)
        assertFalse(dismissed)

        compose.onNodeWithText("Back").performClick()
        compose.onNodeWithText("Back").performClick()
        compose.onNodeWithText("Draft project").assertIsDisplayed()
        compose.onNodeWithText("Cancel").performClick()
        compose.onNodeWithText("Discard changes?").assertIsDisplayed()
        compose.onNodeWithText("Keep editing").performClick()
        compose.onNodeWithText("Draft project").assertIsDisplayed()
        assertFalse(dismissed)
    }

    @Test fun settingsSoundSubpageShowsNotificationStatusAndReturnsHome() {
        val state = AppSnapshot()
        compose.setContent {
            PomodoroTheme(state.settings.appearance) {
                SettingsScreen(state, Platform(), {}, { MutationResult.Success })
            }
        }

        compose.onNodeWithText("Sounds & haptics").performScrollTo().performClick()
        compose.onNodeWithText("Completion alerts").assertIsDisplayed()
        compose.onNodeWithText("Notifications are enabled for Pomodoro.").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Test focus completion alert").assertIsDisplayed()
        compose.onNodeWithContentDescription("Settings").performClick()
        compose.onNodeWithText("Preferences").assertIsDisplayed()
        compose.onNodeWithText("Backup & restore").performScrollTo().assertIsDisplayed()
    }
}
