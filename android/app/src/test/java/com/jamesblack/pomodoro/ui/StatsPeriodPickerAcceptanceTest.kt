package com.jamesblack.pomodoro.ui

import android.app.Application
import android.app.DatePickerDialog
import android.content.DialogInterface
import android.util.TypedValue
import androidx.compose.ui.test.junit4.createComposeRule
import com.jamesblack.pomodoro.core.Appearance
import com.jamesblack.pomodoro.core.StatsDateRange
import com.jamesblack.pomodoro.core.Time
import java.time.LocalDate
import java.time.ZoneId
import java.util.TimeZone
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], application = Application::class, qualifiers = "w412dp-h915dp-notnight-mdpi")
class StatsPeriodPickerAcceptanceTest {
    @get:Rule val compose = createComposeRule()
    private val selected = Time.start(LocalDate.of(2026, 3, 7), ZoneId.systemDefault())
    private val now = Time.start(LocalDate.of(2026, 3, 12), ZoneId.systemDefault()) + 43_200

    @Test fun darkAppearanceUsesDarkCalendarOnLightHost() = assertCalendarTheme(Appearance.dark, false)

    @Test @Config(qualifiers = "w412dp-h915dp-night-mdpi")
    fun lightAppearanceUsesLightCalendarOnDarkHost() = assertCalendarTheme(Appearance.light, true)

    @Test fun systemAppearanceUsesLightCalendarInDayMode() = assertCalendarTheme(Appearance.system, true)

    @Test @Config(qualifiers = "w412dp-h915dp-night-mdpi")
    fun systemAppearanceUsesDarkCalendarInNightMode() = assertCalendarTheme(Appearance.system, false)

    private fun assertCalendarTheme(appearance: Appearance, isLight: Boolean) {
        compose.setContent {
            PomodoroTheme(appearance) {
                StatsPeriodPicker(StatsDateRange.day, selected, null, now, {}, {})
            }
        }
        compose.runOnIdle {
            val dialog = ShadowDialog.getLatestDialog() as DatePickerDialog
            val attribute = TypedValue()
            assertTrue(dialog.context.theme.resolveAttribute(android.R.attr.isLightTheme, attribute, true))
            assertEquals(isLight, attribute.data != 0)
        }
    }

    @Test fun selectingDateKeepsLocalMidnightAndDismissesOnce() {
        val previousZone = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
        try {
            val zone = ZoneId.systemDefault()
            val initial = LocalDate.of(2026, 3, 7)
            val today = LocalDate.of(2026, 3, 12)
            val localNow = Time.start(today, zone) + 43_200
            var chosen: Double? = null
            var dismissals = 0
            compose.setContent {
                PomodoroTheme(Appearance.dark) {
                    StatsPeriodPicker(StatsDateRange.day, Time.start(initial, zone), null, localNow,
                        { dismissals++ }, { chosen = it })
                }
            }
            compose.runOnIdle {
                val dialog = ShadowDialog.getLatestDialog() as DatePickerDialog
                assertEquals(initial.year, dialog.datePicker.year)
                assertEquals(initial.monthValue - 1, dialog.datePicker.month)
                assertEquals(initial.dayOfMonth, dialog.datePicker.dayOfMonth)
                assertEquals(today, java.time.Instant.ofEpochMilli(dialog.datePicker.maxDate).atZone(zone).toLocalDate())
                dialog.datePicker.updateDate(2026, 2, 8)
                dialog.getButton(DialogInterface.BUTTON_POSITIVE).performClick()
            }
            compose.waitForIdle()
            compose.runOnIdle {
                assertEquals(Time.start(LocalDate.of(2026, 3, 8), zone), chosen)
                assertEquals(1, dismissals)
            }
        } finally {
            TimeZone.setDefault(previousZone)
        }
    }

    @Test fun cancellingCalendarDismissesWithoutSelectingDate() {
        var chosen: Double? = null
        var dismissals = 0
        compose.setContent {
            PomodoroTheme(Appearance.dark) {
                StatsPeriodPicker(StatsDateRange.day, selected, null, now, { dismissals++ }, { chosen = it })
            }
        }
        compose.runOnIdle {
            (ShadowDialog.getLatestDialog() as DatePickerDialog).cancel()
        }
        compose.waitForIdle()
        compose.runOnIdle {
            assertNull(chosen)
            assertEquals(1, dismissals)
        }
    }
}
