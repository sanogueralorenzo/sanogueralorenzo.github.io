package com.sanogueralorenzo.voice.settings

enum class AppThemeMode(val storageValue: String) {
    AUTO("auto"),
    LIGHT("light"),
    DARK("dark");

    fun resolveIsDark(systemDark: Boolean): Boolean {
        return when (this) {
            AUTO -> systemDark
            LIGHT -> false
            DARK -> true
        }
    }

    companion object {
        fun fromStorage(value: String?): AppThemeMode {
            return entries.firstOrNull { it.storageValue == value } ?: AUTO
        }
    }
}
