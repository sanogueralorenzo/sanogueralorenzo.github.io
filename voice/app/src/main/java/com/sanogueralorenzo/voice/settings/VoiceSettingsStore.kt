package com.sanogueralorenzo.voice.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.SharedPreferencesMigration
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
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
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

private val Context.voiceSettingsDataStore: DataStore<Preferences> by preferencesDataStore(
    name = VoiceSettingsStore.DATASTORE_NAME,
    produceMigrations = { context ->
        listOf(SharedPreferencesMigration(context, VoiceSettingsStore.LEGACY_PREFS_NAME))
    }
)

/**
 * App-level persisted settings shared by setup UI and IME runtime.
 */
@Inject
@SingleIn(AppScope::class)
class VoiceSettingsStore(context: Context) {
    private val appContext = context.applicationContext
    private val dataStore = appContext.voiceSettingsDataStore
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val rewriteEnabledState = MutableStateFlow(DEFAULT_LITERT_REWRITE_ENABLED)
    private val themeModeState = MutableStateFlow(DEFAULT_THEME_MODE)

    val themeModeFlow: StateFlow<AppThemeMode> = themeModeState

    init {
        val initialSnapshot = runBlocking {
            dataStore.data.first()
        }
        rewriteEnabledState.value = initialSnapshot[KEY_LITERT_REWRITE_ENABLED] ?: DEFAULT_LITERT_REWRITE_ENABLED
        themeModeState.value = AppThemeMode.fromStorage(initialSnapshot[KEY_APP_THEME_MODE])

        scope.launch {
            dataStore.data
                .map { prefs ->
                    Pair(
                        prefs[KEY_LITERT_REWRITE_ENABLED] ?: DEFAULT_LITERT_REWRITE_ENABLED,
                        AppThemeMode.fromStorage(prefs[KEY_APP_THEME_MODE])
                    )
                }
                .collectLatest { (rewriteEnabled, themeMode) ->
                    rewriteEnabledState.value = rewriteEnabled
                    themeModeState.value = themeMode
                }
        }
    }

    fun isLiteRtRewriteEnabled(): Boolean {
        return rewriteEnabledState.value
    }

    fun setLiteRtRewriteEnabled(enabled: Boolean) {
        rewriteEnabledState.value = enabled
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_LITERT_REWRITE_ENABLED] = enabled
            }
        }
    }

    fun themeMode(): AppThemeMode {
        return themeModeState.value
    }

    fun setThemeMode(mode: AppThemeMode) {
        themeModeState.value = mode
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_APP_THEME_MODE] = mode.storageValue
            }
        }
    }

    companion object {
        internal const val LEGACY_PREFS_NAME = "voice_settings"
        internal const val DATASTORE_NAME = "voice_settings_store"
        private val KEY_LITERT_REWRITE_ENABLED = booleanPreferencesKey("litert_rewrite_enabled")
        private val KEY_APP_THEME_MODE = stringPreferencesKey("app_theme_mode")
        private const val DEFAULT_LITERT_REWRITE_ENABLED = true
        private val DEFAULT_THEME_MODE = AppThemeMode.AUTO
    }
}
