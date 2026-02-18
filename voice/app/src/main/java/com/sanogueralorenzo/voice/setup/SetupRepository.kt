package com.sanogueralorenzo.voice.setup

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.core.content.ContextCompat
import com.sanogueralorenzo.voice.ime.VoiceInputMethodService
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.summary.PromptTemplateStore

class SetupRepository(
    context: Context
) {
    data class KeyboardStatus(
        val enabled: Boolean,
        val selected: Boolean
    )

    data class MissingSetupItems(
        val micPermission: Boolean,
        val imeEnabled: Boolean,
        val imeSelected: Boolean,
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
        CHOOSE_KEYBOARD,
        DOWNLOAD_MODELS,
        COMPLETE
    }

    private val appContext = context.applicationContext
    private val promptTemplateStore = PromptTemplateStore(appContext)
    private val voiceImeIdShort = ComponentName(appContext, VoiceInputMethodService::class.java).flattenToShortString()
    private val voiceImeIdLong = ComponentName(appContext, VoiceInputMethodService::class.java).flattenToString()

    fun hasMicPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun keyboardStatus(keyboardSelectionAssumed: Boolean = false): KeyboardStatus {
        val enabled = isVoiceImeEnabled()
        val selected = keyboardSelectionAssumed || isVoiceImeSelectedAsDefault(enabledFallback = enabled)
        return KeyboardStatus(
            enabled = enabled,
            selected = selected
        )
    }

    fun isConnectedToWifi(): Boolean {
        val connectivityManager = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val activeNetwork = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
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

    fun missingSetupItems(keyboardSelectionAssumed: Boolean = false): MissingSetupItems {
        val keyboardStatus = keyboardStatus(keyboardSelectionAssumed = keyboardSelectionAssumed)
        val readiness = readModelReadiness()
        return MissingSetupItems(
            micPermission = !hasMicPermission(),
            imeEnabled = !keyboardStatus.enabled,
            imeSelected = !keyboardStatus.selected,
            liteRtModel = !readiness.liteRtReady,
            moonshineModel = !readiness.moonshineReady,
            promptTemplate = !readiness.promptReady
        )
    }

    fun requiredStep(
        introDismissed: Boolean,
        keyboardSelectionAssumed: Boolean = false
    ): RequiredStep {
        val missing = missingSetupItems(keyboardSelectionAssumed = keyboardSelectionAssumed)
        return requiredStepForMissing(
            missing = missing,
            introDismissed = introDismissed
        )
    }

    suspend fun ensurePromptDownloaded(force: Boolean): PromptTemplateStore.DownloadResult {
        return promptTemplateStore.ensurePromptDownloaded(force = force)
    }

    fun currentPromptVersion(): String? {
        return promptTemplateStore.currentPromptVersion()
    }

    companion object {
        internal fun requiredStepForMissing(
            missing: MissingSetupItems,
            introDismissed: Boolean
        ): RequiredStep {
            if (!introDismissed && missing.allCoreItemsMissing) return RequiredStep.INTRO
            if (missing.micPermission) return RequiredStep.MIC_PERMISSION
            if (missing.imeEnabled) return RequiredStep.ENABLE_KEYBOARD
            if (missing.imeSelected) return RequiredStep.CHOOSE_KEYBOARD
            if (missing.modelsOrPrompt) return RequiredStep.DOWNLOAD_MODELS
            return RequiredStep.COMPLETE
        }
    }

    private fun isVoiceImeEnabled(): Boolean {
        val imm = appContext.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        val enabledViaImm = imm
            ?.enabledInputMethodList
            ?.any { info -> isVoiceImeId(info.id.substringBefore(';').trim()) }
            ?: false
        if (enabledViaImm) return true

        val raw = runCatching {
            Settings.Secure.getString(
                appContext.contentResolver,
                Settings.Secure.ENABLED_INPUT_METHODS
            )
        }.getOrNull().orEmpty()
        if (raw.isBlank()) return false
        return raw.split(':').any { entry ->
            isVoiceImeId(entry.substringBefore(';').trim())
        }
    }

    private fun isVoiceImeSelectedAsDefault(enabledFallback: Boolean): Boolean {
        val selected = runCatching {
            Settings.Secure.getString(
                appContext.contentResolver,
                Settings.Secure.DEFAULT_INPUT_METHOD
            )
        }.getOrNull()?.substringBefore(';')?.trim().orEmpty()
        if (selected.isBlank()) {
            return enabledFallback
        }
        return isVoiceImeId(selected)
    }

    private fun isVoiceImeId(id: String?): Boolean {
        if (id.isNullOrBlank()) return false
        return id == voiceImeIdShort || id == voiceImeIdLong
    }
}
