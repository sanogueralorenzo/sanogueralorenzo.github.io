package com.sanogueralorenzo.voice.di

import android.app.Application
import android.content.Context
import com.sanogueralorenzo.voice.asr.AsrRuntimeStatusStore
import com.sanogueralorenzo.voice.models.ModelUpdateChecker
import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.DependencyGraph
import dev.zacsweers.metro.Provides
import dev.zacsweers.metro.SingleIn

@SingleIn(AppScope::class)
@DependencyGraph(AppScope::class)
interface AppGraph {
    val settingsStore: VoiceSettingsStore
    val asrRuntimeStatusStore: AsrRuntimeStatusStore
    val modelUpdateChecker: ModelUpdateChecker

    @Provides
    fun provideApplicationContext(application: Application): Context = application

    @DependencyGraph.Factory
    fun interface Factory {
        fun create(@Provides application: Application): AppGraph
    }
}
