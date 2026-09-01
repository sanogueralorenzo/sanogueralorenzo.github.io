package com.sanogueralorenzo.voice.overlay

import kotlin.math.roundToInt

internal object OverlayDefaultPosition {
    private const val PORTRAIT_END_OFFSET_DP = 6f
    private const val PORTRAIT_KEYBOARD_TOP_OFFSET_DP = 4.5f
    private const val LANDSCAPE_END_OFFSET_DP = 8f
    private const val LANDSCAPE_KEYBOARD_TOP_OFFSET_DP = 2.5f
    private const val PORTRAIT_FALLBACK_SCREEN_HEIGHT_RATIO = 0.64f
    private const val LANDSCAPE_FALLBACK_SCREEN_HEIGHT_RATIO = 0.48f

    fun calculate(
        displayWidthPx: Int,
        displayHeightPx: Int,
        keyboardTopPx: Int?,
        bubbleSizePx: Int,
        density: Float
    ): Pair<Int, Int> {
        val safeWidth = displayWidthPx.coerceAtLeast(0)
        val safeHeight = displayHeightPx.coerceAtLeast(0)
        val safeBubbleSize = bubbleSizePx.coerceAtLeast(1)
        val isLandscape = safeWidth > safeHeight
        val endOffsetDp = if (isLandscape) {
            LANDSCAPE_END_OFFSET_DP
        } else {
            PORTRAIT_END_OFFSET_DP
        }
        val keyboardOffsetDp = if (isLandscape) {
            LANDSCAPE_KEYBOARD_TOP_OFFSET_DP
        } else {
            PORTRAIT_KEYBOARD_TOP_OFFSET_DP
        }
        val fallbackScreenHeightRatio = if (isLandscape) {
            LANDSCAPE_FALLBACK_SCREEN_HEIGHT_RATIO
        } else {
            PORTRAIT_FALLBACK_SCREEN_HEIGHT_RATIO
        }
        val endOffsetPx = (endOffsetDp * density).roundToInt()
        val keyboardOffsetPx = (keyboardOffsetDp * density).roundToInt()
        val keyboardTop = keyboardTopPx
            ?.takeIf { it in 1 until safeHeight }
            ?: (safeHeight * fallbackScreenHeightRatio).roundToInt()
        val maxX = (safeWidth - safeBubbleSize).coerceAtLeast(0)
        val maxY = (safeHeight - safeBubbleSize).coerceAtLeast(0)
        val x = safeWidth - safeBubbleSize - endOffsetPx
        val y = keyboardTop + keyboardOffsetPx
        return x.coerceIn(0, maxX) to y.coerceIn(0, maxY)
    }
}
