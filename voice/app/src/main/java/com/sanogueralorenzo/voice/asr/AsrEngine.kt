package com.sanogueralorenzo.voice.asr

enum class AsrEngine(
    val id: String,
    val displayName: String,
    val isExperimental: Boolean
) {
    MOONSHINE(
        id = "moonshine",
        displayName = "Moonshine",
        isExperimental = false
    );

    companion object {
        fun fromId(id: String?): AsrEngine {
            return entries.firstOrNull { it.id == id } ?: MOONSHINE
        }
    }
}
