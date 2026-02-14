package com.sanogueralorenzo.voice.asr

import android.content.Context
import androidx.core.content.edit

enum class MoonshineAsrProfile(
    val id: String,
    val displayName: String,
    val transcriptionIntervalSec: String,
    val vadWindowDurationSec: String,
    val vadMaxSegmentDurationSec: String
) {
    FAST(
        id = "fast",
        displayName = "Fast",
        transcriptionIntervalSec = "0.12",
        vadWindowDurationSec = "0.24",
        vadMaxSegmentDurationSec = "6.0"
    ),
    BALANCED(
        id = "balanced",
        displayName = "Balanced",
        transcriptionIntervalSec = "0.16",
        vadWindowDurationSec = "0.30",
        vadMaxSegmentDurationSec = "8.0"
    ),
    ACCURATE(
        id = "accurate",
        displayName = "Accurate",
        transcriptionIntervalSec = "0.24",
        vadWindowDurationSec = "0.36",
        vadMaxSegmentDurationSec = "10.0"
    );

    companion object {
        fun fromId(id: String?): MoonshineAsrProfile {
            return entries.firstOrNull { it.id == id } ?: BALANCED
        }
    }
}

class MoonshineAsrProfileStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun get(): MoonshineAsrProfile {
        return MoonshineAsrProfile.fromId(prefs.getString(KEY_PROFILE, null))
    }

    fun set(profile: MoonshineAsrProfile) {
        prefs.edit { putString(KEY_PROFILE, profile.id) }
    }

    companion object {
        private const val PREFS_NAME = "voice_moonshine_asr_profile_prefs"
        private const val KEY_PROFILE = "moonshine_asr_profile"
    }
}
