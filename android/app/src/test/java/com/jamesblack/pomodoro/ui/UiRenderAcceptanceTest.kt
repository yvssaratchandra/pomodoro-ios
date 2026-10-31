package com.jamesblack.pomodoro.ui

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.runtime.*
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.Density
import com.jamesblack.pomodoro.core.*
import com.jamesblack.pomodoro.core.store.*
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Real Compose renders supplement interaction tests; HTML previews are not app screenshots. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, qualifiers = "w393dp-h852dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class UiRenderAcceptanceTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val now = 815140800.0
    private val work = Project(name = "Work", breadcrumb = ProjectBreadcrumb("Review the experiment notes\nDraft the methods section", now))
    private val reading = Project(name = "Reading")
    private fun fixture(appearance: Appearance) = AppSnapshot(
        projects = listOf(work, reading),
        settings = Settings(appearance = appearance),
        thoughts = listOf(
            CapturedThought(projectID = work.id, createdAt = now - 30, text = "Ask about the design review"),
            CapturedThought(projectID = reading.id, createdAt = now - 60, text = "Compare the two approaches in the paper"),
            CapturedThought(projectID = work.id, createdAt = now - 90, text = "Send the agenda for Monday", completedAt = now - 10)
        ),
        sessions = (1..3).map { index -> FocusSession(newID(), work.id, now - index * 3600, now - index * 3600 + 1500, 1500, SessionOutcome.completed) }
    )
    private class Platform : PlatformActions {
        override val notificationStatus = ""
        override fun requestNotifications() {}
        override fun testSound(kind: TimerKind) {}
        override fun openNotificationSettings() {}
        override fun exportBackup() {}
        override fun importBackup() {}
        override fun pinShortcut(route: AppRoute) {}
    }
    @Test fun renderApprovedScreensInBothAppearances() {
        var snapshot by mutableStateOf(fixture(Appearance.light))
        compose.setContent { key(snapshot.settings.appearance) { PomodoroUi(snapshot, now, null, null, null, {}, { MutationResult.Success }, Platform()) } }
        for (appearance in listOf(Appearance.light, Appearance.dark)) {
            val base = fixture(appearance)
            compose.runOnIdle { snapshot = base }
            compose.onNodeWithText("Start Focus").assertIsDisplayed()
            compose.onNodeWithTag("duration-edit-cue", useUnmergedTree = true).assertExists()
            screenshot("${appearance.name}-focus-ready")
            compose.runOnIdle { snapshot = TimerEngine.startFocus(base, work.id, 25, now - 378) }
            compose.onNodeWithText("18:42").assertIsDisplayed()
            compose.onNodeWithTag("focus-timer").assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo(.748f, 0f..1f)))
            compose.onNodeWithText("End Focus").assertIsDisplayed()
            compose.onNodeWithTag("duration-edit-cue", useUnmergedTree = true).assertDoesNotExist()
            screenshot("${appearance.name}-focus-running")
            compose.runOnIdle { snapshot = base.copy(breakOffer = BreakOffer(work.id, TimerKind.shortBreak, 5)) }
            compose.onNodeWithTag("duration-edit-cue", useUnmergedTree = true).assertExists()
            screenshot("${appearance.name}-break-ready")
            compose.runOnIdle { snapshot = TimerEngine.startBreak(snapshot, now - 102) }
            compose.onNodeWithText("03:18").assertIsDisplayed()
            screenshot("${appearance.name}-break-running")
            compose.runOnIdle { snapshot = base }
            compose.onNodeWithTag("tab-thoughts").performClick()
            compose.onNodeWithText("Ask about the design review").assertIsDisplayed()
            screenshot("${appearance.name}-thoughts")
            compose.onNodeWithTag("tab-stats").performClick()
            screenshot("${appearance.name}-stats")
            compose.onNodeWithText("Week").performClick()
            screenshot("${appearance.name}-stats-week")
            compose.onNodeWithText("Month").performClick()
            screenshot("${appearance.name}-stats-month")
            compose.onNodeWithTag("tab-focus").performClick()
            compose.onNodeWithContentDescription("Projects").performClick()
            screenshot("${appearance.name}-projects")
            compose.onNodeWithTag("tab-focus").performClick()
            compose.onNodeWithContentDescription("Settings").performClick()
            screenshot("${appearance.name}-settings")
        }
    }
    @Test
    @Config(qualifiers = "w360dp-h800dp-mdpi")
    fun narrowLargeTextKeepsFocusActionsReachable() {
        val snapshot = fixture(Appearance.dark).copy(projects = listOf(work.copy(name = "A long project name for accessibility review")))
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 1.5f)) {
                PomodoroUi(snapshot, now, null, null, null, {}, { MutationResult.Success }, Platform())
            }
        }
        compose.onNodeWithText("Start Focus").performScrollTo().assertIsDisplayed()
        screenshot("dark-narrow-large-focus")
    }
    private fun screenshot(name: String) {
        compose.waitForIdle()
        compose.runOnIdle {
            val view = compose.activity.window.decorView
            val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
            view.draw(Canvas(bitmap))
            File("build/reports/screenshots/refined-$name.png").apply { requireNotNull(parentFile).mkdirs() }.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
        }
    }
}
