package com.sanogueralorenzo.voice.keyboard

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.view.inputmethod.InputMethodManager

data class VoiceKeyboardStatus(
    val enabled: Boolean,
    val selected: Boolean
)

object VoiceKeyboardStatusReader {
    fun read(context: Context): VoiceKeyboardStatus {
        val appContext = context.applicationContext
        val component = ComponentName(appContext, VoiceInputMethodService::class.java)
        val shortId = component.flattenToShortString()
        val longId = component.flattenToString()
        fun matches(id: String?): Boolean {
            val normalized = id?.substringBefore(';')?.trim().orEmpty()
            return normalized == shortId || normalized == longId
        }

        val inputMethodManager = appContext.getSystemService(InputMethodManager::class.java)
        val enabled = inputMethodManager?.enabledInputMethodList?.any { info ->
            matches(info.id)
        } == true
        val selected = runCatching {
            Settings.Secure.getString(
                appContext.contentResolver,
                Settings.Secure.DEFAULT_INPUT_METHOD
            )
        }.getOrNull().let(::matches)
        return VoiceKeyboardStatus(enabled = enabled, selected = selected)
    }
}
