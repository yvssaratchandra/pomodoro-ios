package com.jamesblack.pomodoro.ui

import android.Manifest
import android.graphics.Bitmap
import android.graphics.Canvas
import org.robolectric.annotation.GraphicsMode
import java.io.File
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.jamesblack.pomodoro.MainActivity
import com.jamesblack.pomodoro.PomodoroApplication
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = PomodoroApplication::class, qualifiers = "w412dp-h915dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LaunchJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    @Before fun permissions() { shadowOf((RuntimeEnvironment.getApplication() as PomodoroApplication)).grantPermissions(Manifest.permission.POST_NOTIFICATIONS) }
    @Test fun createProjectStartFocusAndCaptureThought() {
        compose.waitUntil(15000) { compose.onAllNodesWithText("Create Project").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Create Project").performClick()
        compose.onNodeWithText("Project name").performTextInput("Work project")
        compose.onNodeWithText("Save", useUnmergedTree = true).performClick()
        compose.waitUntil(15000) { compose.onAllNodesWithText("Start Focus").fetchSemanticsNodes().isNotEmpty() }
        screenshot("focus-idle")
        compose.onNodeWithText("Start Focus").performScrollTo().performClick()
        compose.waitUntil(15000) { compose.onAllNodesWithText("End Focus").fetchSemanticsNodes().isNotEmpty() }
        screenshot("focus-active")
        compose.onNodeWithText("Add a thought").performScrollTo().performClick()
        compose.onNodeWithText("Add a thought…").performTextInput("Ask about the design")
        compose.onNodeWithText("Add thought").performClick()
        compose.waitForIdle()
        assertNull((RuntimeEnvironment.getApplication() as PomodoroApplication).store.errorMessage.value)
        compose.waitUntil(15000) { (RuntimeEnvironment.getApplication() as PomodoroApplication).store.snapshot.thoughts.isNotEmpty() }
        compose.onNodeWithText("Ask about the design").assertIsDisplayed()
        compose.onNodeWithText("Done").performClick()
        compose.onNodeWithText("Thoughts").performClick()
        screenshot("thoughts")
        compose.onNodeWithText("Stats").performClick()
        screenshot("stats")
        val snapshot = (RuntimeEnvironment.getApplication() as PomodoroApplication).store.snapshot
        assertEquals("Work project", snapshot.projects.single().name)
        assertNotNull(snapshot.activeTimer)
        assertEquals(snapshot.activeTimer!!.id, snapshot.thoughts.single().originSessionID)
        assertEquals(snapshot.projects.single().id, snapshot.thoughts.single().projectID)
    }
    @Test fun unsavedProjectDraftSurvivesActivityRecreation() {
        compose.waitUntil(15000) { compose.onAllNodesWithText("Create Project").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Create Project").performClick()
        compose.onNodeWithText("Project name").performTextInput("Draft before rotation")
        compose.activityRule.scenario.recreate()
        compose.onNodeWithText("New project").assertIsDisplayed()
        compose.onNodeWithText("Draft before rotation").assertIsDisplayed()
        assertTrue((RuntimeEnvironment.getApplication() as PomodoroApplication).store.snapshot.projects.isEmpty())
    }
    private fun screenshot(name: String) {
        compose.waitForIdle()
        val file = File("/tmp/pomodoro-android-$name.png")
        compose.runOnIdle {
            val view = compose.activity.window.decorView
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
    }

}
