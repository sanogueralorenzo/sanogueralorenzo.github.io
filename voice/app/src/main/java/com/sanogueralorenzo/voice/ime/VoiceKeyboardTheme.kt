package com.sanogueralorenzo.voice.ime

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

internal data class VoiceKeyboardColors(
    val keyboardBackground: Color,
    val idlePill: Color,
    val activePill: Color,
    val activeVisualizer: Color,
    val actionContainer: Color,
    val actionIcon: Color,
    val idleAuxContainer: Color,
    val idleAuxContainerActive: Color,
    val idleAuxIcon: Color,
    val idleDebugInactiveAlpha: Float
)

@Composable
internal fun rememberVoiceKeyboardColors(): VoiceKeyboardColors {
    val isDarkTheme = isSystemInDarkTheme()
    val scheme = MaterialTheme.colorScheme
    return if (isDarkTheme) {
        VoiceKeyboardColors(
            keyboardBackground = scheme.surface,
            idlePill = Color(0xFF78808A),
            activePill = Color(0xFF1A2026),
            activeVisualizer = Color.White,
            actionContainer = Color(0x33FFFFFF),
            actionIcon = Color.White,
            idleAuxContainer = Color(0x29FFFFFF),
            idleAuxContainerActive = Color(0x52FFFFFF),
            idleAuxIcon = Color.White,
            idleDebugInactiveAlpha = 0.65f
        )
    } else {
        VoiceKeyboardColors(
            keyboardBackground = Color(0xFFE8EAED),
            idlePill = Color(0xFFA9B0B8),
            activePill = Color(0xFFF6F7F8),
            activeVisualizer = Color(0xFF202124),
            actionContainer = Color(0x1F000000),
            actionIcon = Color(0xFF202124),
            idleAuxContainer = Color(0x26000000),
            idleAuxContainerActive = Color(0x3D000000),
            idleAuxIcon = Color(0xFF202124),
            idleDebugInactiveAlpha = 0.82f
        )
    }
}
