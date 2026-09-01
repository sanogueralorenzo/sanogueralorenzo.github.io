package com.sanogueralorenzo.voice.overlay

import org.junit.Assert.assertEquals
import org.junit.Test

class OverlayDefaultPositionTest {
    @Test
    fun anchorsToSamsungKeyboardBorderAndScreenEnd() {
        assertEquals(
            962 to 1501,
            OverlayDefaultPosition.calculate(
                displayWidthPx = 1080,
                displayHeightPx = 2340,
                imeBottomInsetPx = 852,
                bubbleSizePx = 101,
                density = 450f / 160f
            )
        )
    }

    @Test
    fun scalesOffsetsWithDisplayDensity() {
        assertEquals(
            916 to 1209,
            OverlayDefaultPosition.calculate(
                displayWidthPx = 1000,
                displayHeightPx = 2000,
                imeBottomInsetPx = 800,
                bubbleSizePx = 72,
                density = 2f
            )
        )
    }
}
