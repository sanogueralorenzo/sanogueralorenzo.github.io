package com.sanogueralorenzo.voice.models

import android.content.Context
import com.sanogueralorenzo.voice.audio.DictationLanguage
import com.sanogueralorenzo.voice.connectivity.ConnectivityRepository
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlinx.coroutines.flow.StateFlow

@Inject
@SingleIn(AppScope::class)
class ModelSetupRepository(
    context: Context,
    private val connectivityRepository: ConnectivityRepository
) {
    private val appContext = context.applicationContext
    val wifiConnected: StateFlow<Boolean> = connectivityRepository.wifiConnected

    fun isConnectedToWifi(): Boolean = connectivityRepository.isConnectedToWifi()

    fun readDownloadedLanguages(): Set<DictationLanguage> {
        return DictationLanguage.entries.filterTo(linkedSetOf()) { language ->
            ModelCatalog.moonshineStreamingSpecsFor(language).all { spec ->
                ModelStore.isModelReadyStrict(appContext, spec)
            }
        }
    }
}
