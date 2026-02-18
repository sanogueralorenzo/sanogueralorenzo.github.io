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
    private val llmRewriteEnabledState = MutableStateFlow(DEFAULT_LLM_REWRITE_ENABLED)
    private val capitalizeSentencesEnabledState = MutableStateFlow(DEFAULT_CAPITALIZE_SENTENCES_ENABLED)
    private val removeDotAtEndEnabledState = MutableStateFlow(DEFAULT_REMOVE_DOT_AT_END_ENABLED)

    init {
        val initialSnapshot = runBlocking {
            dataStore.data.first()
        }
        llmRewriteEnabledState.value = initialSnapshot[KEY_LLM_REWRITE_ENABLED] ?: DEFAULT_LLM_REWRITE_ENABLED
        capitalizeSentencesEnabledState.value =
            initialSnapshot[KEY_CAPITALIZE_SENTENCES_ENABLED] ?: DEFAULT_CAPITALIZE_SENTENCES_ENABLED
        removeDotAtEndEnabledState.value =
            initialSnapshot[KEY_REMOVE_DOT_AT_END_ENABLED] ?: DEFAULT_REMOVE_DOT_AT_END_ENABLED

        scope.launch {
            dataStore.data.collectLatest { prefs ->
                llmRewriteEnabledState.value = prefs[KEY_LLM_REWRITE_ENABLED] ?: DEFAULT_LLM_REWRITE_ENABLED
                capitalizeSentencesEnabledState.value =
                    prefs[KEY_CAPITALIZE_SENTENCES_ENABLED] ?: DEFAULT_CAPITALIZE_SENTENCES_ENABLED
                removeDotAtEndEnabledState.value =
                    prefs[KEY_REMOVE_DOT_AT_END_ENABLED] ?: DEFAULT_REMOVE_DOT_AT_END_ENABLED
            }
        }
    }

    fun isLlmRewriteEnabled(): Boolean {
        return llmRewriteEnabledState.value
    }

    fun setLlmRewriteEnabled(enabled: Boolean) {
        llmRewriteEnabledState.value = enabled
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_LLM_REWRITE_ENABLED] = enabled
            }
        }
    }

    fun isCapitalizeSentencesEnabled(): Boolean {
        return capitalizeSentencesEnabledState.value
    }

    fun setCapitalizeSentencesEnabled(enabled: Boolean) {
        capitalizeSentencesEnabledState.value = enabled
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_CAPITALIZE_SENTENCES_ENABLED] = enabled
            }
        }
    }

    fun isRemoveDotAtEndEnabled(): Boolean {
        return removeDotAtEndEnabledState.value
    }

    fun setRemoveDotAtEndEnabled(enabled: Boolean) {
        removeDotAtEndEnabledState.value = enabled
        scope.launch {
            dataStore.edit { prefs ->
                prefs[KEY_REMOVE_DOT_AT_END_ENABLED] = enabled
            }
        }
    }

    companion object {
        internal const val DATASTORE_NAME = "preferences_store"
        private val KEY_LLM_REWRITE_ENABLED = booleanPreferencesKey("llm_rewrite_enabled")
        private val KEY_CAPITALIZE_SENTENCES_ENABLED = booleanPreferencesKey("capitalize_sentences_enabled")
        private val KEY_REMOVE_DOT_AT_END_ENABLED = booleanPreferencesKey("remove_dot_at_end_enabled")
        private const val DEFAULT_LLM_REWRITE_ENABLED = true
        private const val DEFAULT_CAPITALIZE_SENTENCES_ENABLED = false
        private const val DEFAULT_REMOVE_DOT_AT_END_ENABLED = false
    }
}
