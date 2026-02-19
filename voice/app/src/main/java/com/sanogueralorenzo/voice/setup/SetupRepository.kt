package com.sanogueralorenzo.voice.setup

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.core.content.ContextCompat
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import com.sanogueralorenzo.voice.connectivity.ConnectivityRepository
import com.sanogueralorenzo.voice.ime.VoiceInputMethodService
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.summary.PromptTemplateStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.runBlocking

private val Context.setupDataStore: DataStore<Preferences> by preferencesDataStore(
    name = SetupRepository.SETUP_DATASTORE_NAME
)

data class ModelReadiness(
    val liteRtReady: Boolean,
    val moonshineReady: Boolean,
    val promptReady: Boolean,
    val promptVersion: String?
)

class SetupRepository(
    context: Context,
    private val connectivityRepository: ConnectivityRepository
) {
    data class KeyboardStatus(
        val enabled: Boolean,
        val selected: Boolean
    )

    data class MissingSetupItems(
        val micPermission: Boolean,
        val imeEnabled: Boolean,
        val liteRtModel: Boolean,
        val moonshineModel: Boolean,
        val promptTemplate: Boolean
    ) {
        val modelsOrPrompt: Boolean
            get() = liteRtModel || moonshineModel || promptTemplate

        val allCoreItemsMissing: Boolean
            get() = micPermission && imeEnabled && liteRtModel && moonshineModel && promptTemplate
    }

    enum class RequiredStep {
        INTRO,
        MIC_PERMISSION,
        ENABLE_KEYBOARD,
        DOWNLOAD_MODELS,
        SELECT_KEYBOARD,
        COMPLETE
    }

    private val appContext = context.applicationContext
    private val promptTemplateStore = PromptTemplateStore(appContext)
    private val dataStore = appContext.setupDataStore
    private val voiceImeIdShort = ComponentName(appContext, VoiceInputMethodService::class.java).flattenToShortString()
    private val voiceImeIdLong = ComponentName(appContext, VoiceInputMethodService::class.java).flattenToString()
    val wifiConnected: StateFlow<Boolean> = connectivityRepository.wifiConnected

    fun hasMicPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun keyboardStatus(): KeyboardStatus {
        val enabled = isVoiceImeEnabled()
        val selected = isVoiceImeSelectedAsDefault()
        return KeyboardStatus(
            enabled = enabled,
            selected = selected
        )
    }

    fun isConnectedToWifi(): Boolean {
        return connectivityRepository.isConnectedToWifi()
    }

    fun readModelReadiness(): ModelReadiness {
        val liteRtReady = ModelStore.isModelReadyStrict(appContext, ModelCatalog.liteRtLm)
        val moonshineReady = ModelCatalog.moonshineMediumStreamingSpecs.all {
            ModelStore.isModelReadyStrict(appContext, it)
        }
        return ModelReadiness(
            liteRtReady = liteRtReady,
            moonshineReady = moonshineReady,
            promptReady = promptTemplateStore.isPromptReady(),
            promptVersion = promptTemplateStore.currentPromptVersion()
        )
    }

    fun missingSetupItems(): MissingSetupItems {
        val keyboardStatus = keyboardStatus()
        val readiness = readModelReadiness()
        return MissingSetupItems(
            micPermission = !hasMicPermission(),
            imeEnabled = !keyboardStatus.enabled,
            liteRtModel = !readiness.liteRtReady,
            moonshineModel = !readiness.moonshineReady,
            promptTemplate = !readiness.promptReady
        )
    }

    fun requiredStep(
        introDismissed: Boolean
    ): RequiredStep {
        val missing = missingSetupItems()
        val setupComplete = isSetupComplete()
        return requiredStepForMissing(
            missing = missing,
            introDismissed = introDismissed,
            setupComplete = setupComplete
        )
    }

    suspend fun ensurePromptDownloaded(force: Boolean): PromptTemplateStore.DownloadResult {
        return promptTemplateStore.ensurePromptDownloaded(force = force)
    }

    fun currentPromptVersion(): String? {
        return promptTemplateStore.currentPromptVersion()
    }

    fun isSetupComplete(): Boolean {
        val snapshot = runBlocking { dataStore.data.first() }
        return snapshot[KEY_SETUP_COMPLETE] ?: false
    }

    suspend fun setSetupComplete(complete: Boolean) {
        dataStore.edit { prefs ->
            prefs[KEY_SETUP_COMPLETE] = complete
        }
    }

    companion object {
        internal const val SETUP_DATASTORE_NAME = "setup_store"
        private val KEY_SETUP_COMPLETE = booleanPreferencesKey("setup_complete")

        internal fun requiredStepForMissing(
            missing: MissingSetupItems,
            introDismissed: Boolean,
            setupComplete: Boolean
        ): RequiredStep {
            if (!introDismissed && missing.allCoreItemsMissing) return RequiredStep.INTRO
            if (missing.modelsOrPrompt) return RequiredStep.DOWNLOAD_MODELS
            if (missing.micPermission) return RequiredStep.MIC_PERMISSION
            if (missing.imeEnabled) return RequiredStep.ENABLE_KEYBOARD
            if (!setupComplete) return RequiredStep.SELECT_KEYBOARD
            return RequiredStep.COMPLETE
        }
    }

    private fun isVoiceImeEnabled(): Boolean {
        val imm = appContext.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        return imm
            ?.enabledInputMethodList
            ?.any { info -> isVoiceImeId(info.id.substringBefore(';').trim()) }
            ?: false
    }

    private fun isVoiceImeSelectedAsDefault(): Boolean {
        val selected = runCatching {
            Settings.Secure.getString(
                appContext.contentResolver,
                Settings.Secure.DEFAULT_INPUT_METHOD
            )
        }.getOrNull()?.substringBefore(';')?.trim().orEmpty()
        return isVoiceImeId(selected)
    }

    private fun isVoiceImeId(id: String?): Boolean {
        if (id.isNullOrBlank()) return false
        return id == voiceImeIdShort || id == voiceImeIdLong
    }
}
