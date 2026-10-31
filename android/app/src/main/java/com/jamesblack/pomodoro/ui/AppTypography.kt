package com.jamesblack.pomodoro.ui

import androidx.compose.material3.Typography
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.jamesblack.pomodoro.R

@OptIn(ExperimentalTextApi::class)
private fun bundledFamily(resource: Int, weights: List<FontWeight>) = FontFamily(
    weights.map { weight ->
        Font(resource, weight = weight, variationSettings = FontVariation.Settings(FontVariation.weight(weight.weight)))
    }
)

private val InterfaceFontFamily = bundledFamily(
    R.font.inter, listOf(FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold, FontWeight.Bold)
)
internal val TimerFontFamily = bundledFamily(R.font.nunito, listOf(FontWeight.SemiBold))

private fun textStyle(size: Int, lineHeight: Int, weight: FontWeight = FontWeight.Normal) = TextStyle(
    fontFamily = InterfaceFontFamily, fontWeight = weight, fontSize = size.sp, lineHeight = lineHeight.sp,
    letterSpacing = 0.sp
)

// Match the app's SwiftUI text roles while retaining Android font scaling.
internal val AppTypography = Typography(
    displayLarge = textStyle(58, 64, FontWeight.SemiBold),
    displayMedium = textStyle(34, 41, FontWeight.SemiBold),
    displaySmall = textStyle(28, 34),
    headlineLarge = textStyle(34, 41, FontWeight.Bold),
    headlineMedium = textStyle(28, 34),
    headlineSmall = textStyle(22, 28),
    titleLarge = textStyle(20, 25),
    titleMedium = textStyle(17, 22, FontWeight.SemiBold),
    titleSmall = textStyle(15, 20, FontWeight.SemiBold),
    bodyLarge = textStyle(17, 22),
    bodyMedium = textStyle(17, 22),
    bodySmall = textStyle(13, 18),
    labelLarge = textStyle(17, 22),
    labelMedium = textStyle(13, 18, FontWeight.Medium),
    labelSmall = textStyle(12, 16)
)
