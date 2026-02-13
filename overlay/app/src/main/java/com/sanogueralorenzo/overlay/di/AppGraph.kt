package com.sanogueralorenzo.overlay.di

import android.app.Application
import android.content.Context
import com.sanogueralorenzo.overlay.SettingsRepository
import com.sanogueralorenzo.overlay.autotimeout.AutoTimeoutRepository
import com.sanogueralorenzo.overlay.overlay.OverlayRepository
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.DependencyGraph
import dev.zacsweers.metro.Provides
import dev.zacsweers.metro.SingleIn

@SingleIn(AppScope::class)
@DependencyGraph(AppScope::class)
interface AppGraph {
    val overlayRepository: OverlayRepository
    val autoTimeoutRepository: AutoTimeoutRepository
    val settingsRepository: SettingsRepository

    @Provides
    fun provideApplicationContext(application: Application): Context = application

    @DependencyGraph.Factory
    fun interface Factory {
        fun create(@Provides application: Application): AppGraph
    }
}
