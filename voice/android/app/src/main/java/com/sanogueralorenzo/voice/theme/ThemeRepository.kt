package com.sanogueralorenzo.voice.theme

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

enum class KeyboardThemeMode(val storageValue: String) {
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
        fun fromStorage(value: String?): KeyboardThemeMode {
            return entries.firstOrNull { it.storageValue == value } ?: AUTO
        }
    }
}

private val Context.keyboardThemeDataStore: DataStore<Preferences> by preferencesDataStore(
    name = ThemeRepository.DATASTORE_NAME
)

@Inject
@SingleIn(AppScope::class)
class ThemeRepository(context: Context) {
    private val appContext = context.applicationContext
    private val dataStore = appContext.keyboardThemeDataStore
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val keyboardThemeModeState = MutableStateFlow(DEFAULT_THEME_MODE)

    val keyboardThemeModeFlow: StateFlow<KeyboardThemeMode> = keyboardThemeModeState

    init {
        val initialSnapshot = runBlocking { dataStore.data.first() }
        keyboardThemeModeState.value = KeyboardThemeMode.fromStorage(
            value = initialSnapshot[KEY_KEYBOARD_THEME_MODE]
        )
        scope.launch {
            dataStore.data.collectLatest { prefs ->
                keyboardThemeModeState.value = KeyboardThemeMode.fromStorage(
                    value = prefs[KEY_KEYBOARD_THEME_MODE]
                )
            }
        }
    }

    fun keyboardThemeMode(): KeyboardThemeMode {
        return keyboardThemeModeState.value
    }

    fun setKeyboardThemeMode(mode: KeyboardThemeMode) {
        keyboardThemeModeState.value = mode
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_KEYBOARD_THEME_MODE] = mode.storageValue
            }
        }
    }

    companion object {
        internal const val DATASTORE_NAME = "keyboard_theme_store"
        private val KEY_KEYBOARD_THEME_MODE = stringPreferencesKey("keyboard_theme_mode")
        private val DEFAULT_THEME_MODE = KeyboardThemeMode.AUTO
    }
}
