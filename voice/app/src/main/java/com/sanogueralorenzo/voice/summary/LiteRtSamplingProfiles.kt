package com.sanogueralorenzo.voice.summary

import com.sanogueralorenzo.voice.settings.ResponseStyle

internal data class LiteRtSamplingProfile(
    val topK: Int,
    val topP: Double,
    val temperature: Double,
    val useDynamicSeed: Boolean
)

internal object LiteRtSamplingProfiles {
    const val DEFAULT_TOP_K = 1
    const val DEFAULT_TOP_P = 1.0
    const val DEFAULT_TEMPERATURE = 0.0
    const val DEFAULT_SEED = 42

    fun profileForLevel(level: Int): LiteRtSamplingProfile {
        return when (ResponseStyle.normalize(level)) {
            0 -> LiteRtSamplingProfile(
                topK = DEFAULT_TOP_K,
                topP = DEFAULT_TOP_P,
                temperature = DEFAULT_TEMPERATURE,
                useDynamicSeed = false
            )
            1 -> LiteRtSamplingProfile(topK = 4, topP = 0.90, temperature = 0.15, useDynamicSeed = true)
            2 -> LiteRtSamplingProfile(topK = 8, topP = 0.92, temperature = 0.30, useDynamicSeed = true)
            3 -> LiteRtSamplingProfile(topK = 16, topP = 0.95, temperature = 0.50, useDynamicSeed = true)
            4 -> LiteRtSamplingProfile(topK = 32, topP = 0.98, temperature = 0.80, useDynamicSeed = true)
            else -> LiteRtSamplingProfile(topK = 40, topP = 1.0, temperature = 1.10, useDynamicSeed = true)
        }
    }
}
