package com.sanogueralorenzo.voice.settings

object ResponseStyle {
    const val MIN_LEVEL = 0
    const val MAX_LEVEL = 5
    const val DEFAULT_LEVEL = 0
    const val LEVEL_COUNT = MAX_LEVEL - MIN_LEVEL + 1

    fun normalize(level: Int): Int {
        return level.coerceIn(MIN_LEVEL, MAX_LEVEL)
    }
}
