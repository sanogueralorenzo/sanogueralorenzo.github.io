package com.sanogueralorenzo.voice.overlay

import kotlin.math.roundToInt

internal object OverlayDefaultPosition {
    private const val END_OFFSET_DP = 6f
    private const val KEYBOARD_TOP_OFFSET_DP = 4.5f
    private const val FALLBACK_SCREEN_HEIGHT_RATIO = 0.64f

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
        val endOffsetPx = (END_OFFSET_DP * density).roundToInt()
        val keyboardOffsetPx = (KEYBOARD_TOP_OFFSET_DP * density).roundToInt()
        val keyboardTop = keyboardTopPx
            ?.takeIf { it in 1 until safeHeight }
            ?: (safeHeight * FALLBACK_SCREEN_HEIGHT_RATIO).roundToInt()
        val maxX = (safeWidth - safeBubbleSize).coerceAtLeast(0)
        val maxY = (safeHeight - safeBubbleSize).coerceAtLeast(0)
        val x = safeWidth - safeBubbleSize - endOffsetPx
        val y = keyboardTop + keyboardOffsetPx
        return x.coerceIn(0, maxX) to y.coerceIn(0, maxY)
    }
}
