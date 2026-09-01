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
                keyboardTopPx = 1488,
                bubbleSizePx = 101,
                density = 450f / 160f
            )
        )
    }

    @Test
    fun anchorsToSamsungKeyboardInLandscape() {
        assertEquals(
            2216 to 524,
            OverlayDefaultPosition.calculate(
                displayWidthPx = 2340,
                displayHeightPx = 1080,
                keyboardTopPx = 517,
                bubbleSizePx = 101,
                density = 450f / 160f
            )
        )
    }

    @Test
    fun usesLandscapeFallbackWhenKeyboardBoundsAreUnavailable() {
        assertEquals(
            2216 to 525,
            OverlayDefaultPosition.calculate(
                displayWidthPx = 2340,
                displayHeightPx = 1080,
                keyboardTopPx = null,
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
                keyboardTopPx = 1200,
                bubbleSizePx = 72,
                density = 2f
            )
        )
    }

    @Test
    fun usesFallbackWhenKeyboardBoundsAreUnavailable() {
        assertEquals(
            962 to 1511,
            OverlayDefaultPosition.calculate(
                displayWidthPx = 1080,
                displayHeightPx = 2340,
                keyboardTopPx = null,
                bubbleSizePx = 101,
                density = 450f / 160f
            )
        )
    }
}
