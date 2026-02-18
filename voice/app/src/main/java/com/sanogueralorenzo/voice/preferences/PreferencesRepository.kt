package com.sanogueralorenzo.voice.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

private val Context.preferencesDataStore: DataStore<Preferences> by preferencesDataStore(
    name = PreferencesRepository.DATASTORE_NAME
)

@Inject
@SingleIn(AppScope::class)
class PreferencesRepository(
    context: Context
) {
    private val appContext = context.applicationContext
    private val dataStore = appContext.preferencesDataStore
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val rewriteEnabledState = MutableStateFlow(DEFAULT_REWRITE_ENABLED)

    init {
        val initialSnapshot = runBlocking {
            dataStore.data.first()
        }
        rewriteEnabledState.value = initialSnapshot[KEY_REWRITE_ENABLED] ?: DEFAULT_REWRITE_ENABLED

        scope.launch {
            dataStore.data.collectLatest { prefs ->
                rewriteEnabledState.value = prefs[KEY_REWRITE_ENABLED] ?: DEFAULT_REWRITE_ENABLED
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
                prefs[KEY_REWRITE_ENABLED] = enabled
            }
        }
    }

    companion object {
        internal const val DATASTORE_NAME = "preferences_store"
        private val KEY_REWRITE_ENABLED = booleanPreferencesKey("rewrite_enabled")
        private const val DEFAULT_REWRITE_ENABLED = true
    }
}
