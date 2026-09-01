package com.sanogueralorenzo.voice.models

import android.content.Context
import com.sanogueralorenzo.voice.audio.DictationLanguagePreferences
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
    private val connectivityRepository: ConnectivityRepository,
    private val languagePreferences: DictationLanguagePreferences
) {
    private val appContext = context.applicationContext
    val wifiConnected: StateFlow<Boolean> = connectivityRepository.wifiConnected

    fun isConnectedToWifi(): Boolean = connectivityRepository.isConnectedToWifi()

    fun readModelReadiness(): ModelReadiness {
        val moonshineReady = languagePreferences.read().ordered.all { language ->
            ModelCatalog.moonshineStreamingSpecsFor(language).all { spec ->
                ModelStore.isModelReadyStrict(appContext, spec)
            }
        }
        return ModelReadiness(
            moonshineReady = moonshineReady
        )
    }
}
