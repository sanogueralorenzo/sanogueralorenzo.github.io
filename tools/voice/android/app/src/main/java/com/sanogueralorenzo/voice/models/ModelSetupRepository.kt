package com.sanogueralorenzo.voice.models

import android.content.Context
import com.sanogueralorenzo.voice.connectivity.ConnectivityRepository
import kotlinx.coroutines.flow.StateFlow

data class ModelReadiness(
    val moonshineReady: Boolean
) {
    val allReady: Boolean
        get() = moonshineReady
}

class ModelSetupRepository(
    context: Context,
    private val connectivityRepository: ConnectivityRepository
) {
    private val appContext = context.applicationContext
    val wifiConnected: StateFlow<Boolean> = connectivityRepository.wifiConnected

    fun isConnectedToWifi(): Boolean = connectivityRepository.isConnectedToWifi()

    fun readModelReadiness(): ModelReadiness {
        val moonshineReady = ModelCatalog.moonshineStreamingSpecs.all {
            ModelStore.isModelReadyStrict(appContext, it)
        }
        return ModelReadiness(
            moonshineReady = moonshineReady
        )
    }
}
