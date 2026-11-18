package com.sanogueralorenzo.voice.overlay

import com.airbnb.mvrx.Success
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OverlayPositionStateTest {
    @Test
    fun positionIsHiddenUntilConfigLoads() {
        assertFalse(OverlayPositionState().positionLoaded)
    }

    @Test
    fun positionIsReadyAfterConfigLoads() {
        assertTrue(
            OverlayPositionState(
                positionConfig = Success(
                    OverlayConfig(
                        overlayEnabled = true,
                        bubbleX = 120,
                        bubbleY = 240,
                        bubbleSizeDp = 36,
                        hasCustomBubblePosition = true
                    )
                )
            ).positionLoaded
        )
    }
}
