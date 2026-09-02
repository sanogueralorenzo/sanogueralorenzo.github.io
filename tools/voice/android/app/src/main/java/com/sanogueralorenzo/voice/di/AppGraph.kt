package com.sanogueralorenzo.voice.di

import android.app.Application
import android.content.Context
import com.sanogueralorenzo.voice.audio.DictationLanguagePreferences
import com.sanogueralorenzo.voice.connectivity.ConnectivityRepository
import com.sanogueralorenzo.voice.models.ModelSetupRepository
import com.sanogueralorenzo.voice.overlay.OverlayRepository
import com.sanogueralorenzo.voice.product.VoiceInputTypePreferences
import com.sanogueralorenzo.voice.setup.VoiceSetupRepository
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.DependencyGraph
import dev.zacsweers.metro.Provides
import dev.zacsweers.metro.SingleIn

@SingleIn(AppScope::class)
@DependencyGraph(AppScope::class)
interface AppGraph {
    val connectivityRepository: ConnectivityRepository
    val languagePreferences: DictationLanguagePreferences
    val modelSetupRepository: ModelSetupRepository
    val overlayRepository: OverlayRepository
    val voiceInputTypePreferences: VoiceInputTypePreferences
    val voiceSetupRepository: VoiceSetupRepository

    @Provides
    fun provideApplicationContext(application: Application): Context = application

    @DependencyGraph.Factory
    fun interface Factory {
        fun create(@Provides application: Application): AppGraph
    }
}
