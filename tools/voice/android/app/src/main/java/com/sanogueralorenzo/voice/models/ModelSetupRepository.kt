package com.sanogueralorenzo.voice.models

import android.content.Context
import com.sanogueralorenzo.voice.connectivity.ConnectivityRepository
import com.sanogueralorenzo.voice.prompt.PromptTemplateStore
import kotlinx.coroutines.flow.StateFlow

data class ModelReadiness(
    val liteRtReady: Boolean,
    val moonshineReady: Boolean,
    val promptReady: Boolean,
    val promptVersion: String?
) {
    val allReady: Boolean
        get() = liteRtReady && moonshineReady && promptReady
}

class ModelSetupRepository(
    context: Context,
    private val connectivityRepository: ConnectivityRepository
) {
    private val appContext = context.applicationContext
    private val promptTemplateStore = PromptTemplateStore(appContext)

    val wifiConnected: StateFlow<Boolean> = connectivityRepository.wifiConnected

    fun isConnectedToWifi(): Boolean = connectivityRepository.isConnectedToWifi()

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

    suspend fun ensurePromptDownloaded(force: Boolean): PromptTemplateStore.DownloadResult {
        return promptTemplateStore.ensurePromptDownloaded(force = force)
    }
}
