package com.sanogueralorenzo.voice.keyboard

internal object KeyboardSpeechGate {
    fun isActive(currentlyActive: Boolean, audioLevel: Float): Boolean {
        val threshold = if (currentlyActive) RELEASE_THRESHOLD else ATTACK_THRESHOLD
        return audioLevel >= threshold
    }

    private const val ATTACK_THRESHOLD = 0.08f
    private const val RELEASE_THRESHOLD = 0.04f
}
