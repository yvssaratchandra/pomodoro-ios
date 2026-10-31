package com.jamesblack.pomodoro.ui

import android.app.Application
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import com.jamesblack.pomodoro.core.Appearance
import com.jamesblack.pomodoro.core.store.AppCommand
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, qualifiers = "w393dp-h852dp-mdpi")
class EndFocusDialogAcceptanceTest {
    @get:Rule val compose = createComposeRule()

    @Test fun allActionsFitInACompactFullWidthStack() {
        compose.setContent {
            PomodoroTheme(Appearance.dark) { EndFocusDialog("timer", {}, {}) }
        }
        val actions = listOf("Save Session", "Keep Focusing", "Discard Session").map {
            compose.onNodeWithText(it).assertIsDisplayed().getUnclippedBoundsInRoot()
        }
        actions.zipWithNext().forEach { (above, below) ->
            assertEquals(above.left.value, below.left.value, .1f)
            assertEquals(above.right.value, below.right.value, .1f)
            assertEquals(4f, below.top.value - above.bottom.value, .1f)
        }
    }

    @Test fun actionsDismissBeforeSendingTheirOriginalCommand() {
        var visible by mutableStateOf(true)
        val commands = mutableListOf<AppCommand>()
        compose.setContent {
            PomodoroTheme(Appearance.light) {
                if (visible) EndFocusDialog("original-timer", { visible = false }) {
                    assertFalse(visible)
                    commands += it
                }
            }
        }
        compose.onNodeWithText("Keep Focusing").performClick()
        compose.onNodeWithText("End this focus session?").assertDoesNotExist()
        assertTrue(commands.isEmpty())
        compose.runOnIdle { visible = true }
        compose.onNodeWithText("Save Session").performClick()
        compose.onNodeWithText("End this focus session?").assertDoesNotExist()
        assertEquals(listOf(AppCommand.EndTimer), commands)
        compose.runOnIdle { visible = true }
        compose.onNodeWithText("Discard Session").performClick()
        compose.onNodeWithText("End this focus session?").assertDoesNotExist()
        assertEquals(listOf(AppCommand.EndTimer, AppCommand.DiscardFocus("original-timer")), commands)
    }

    @Test
    @Config(qualifiers = "w320dp-h480dp-mdpi")
    fun largeTextOnAShortScreenKeepsEveryActionReachable() {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 2f)) {
                PomodoroTheme(Appearance.dark) { EndFocusDialog("timer", {}, {}) }
            }
        }
        listOf("Save Session", "Keep Focusing", "Discard Session").forEach {
            compose.onNodeWithText(it).performScrollTo().assertIsDisplayed().assertHasClickAction()
        }
    }
}
