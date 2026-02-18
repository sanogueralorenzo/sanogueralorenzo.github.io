package com.sanogueralorenzo.voice.di

import android.app.Application
import android.content.Context
import com.sanogueralorenzo.voice.asr.AsrRuntimeStatusStore
import com.sanogueralorenzo.voice.connectivity.ConnectivityRepository
import com.sanogueralorenzo.voice.models.ModelUpdateChecker
import com.sanogueralorenzo.voice.theme.ThemeRepository
import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import com.sanogueralorenzo.voice.setup.SetupRepository
import com.sanogueralorenzo.voice.summary.DeterministicComposeRewriter
import com.sanogueralorenzo.voice.summary.LiteRtComposeLlmGate
import com.sanogueralorenzo.voice.summary.LiteRtComposePolicy
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.DependencyGraph
import dev.zacsweers.metro.Provides
import dev.zacsweers.metro.SingleIn

@SingleIn(AppScope::class)
@DependencyGraph(AppScope::class)
interface AppGraph {
    val settingsStore: VoiceSettingsStore
    val themeRepository: ThemeRepository
    val asrRuntimeStatusStore: AsrRuntimeStatusStore
    val modelUpdateChecker: ModelUpdateChecker
    val liteRtComposePolicy: LiteRtComposePolicy
    val deterministicComposeRewriter: DeterministicComposeRewriter
    val liteRtComposeLlmGate: LiteRtComposeLlmGate
    val connectivityRepository: ConnectivityRepository
    val setupRepository: SetupRepository

    @Provides
    fun provideApplicationContext(application: Application): Context = application

    @Provides
    fun provideLiteRtComposePolicy(): LiteRtComposePolicy = LiteRtComposePolicy()

    @Provides
    fun provideDeterministicComposeRewriter(): DeterministicComposeRewriter = DeterministicComposeRewriter()

    @Provides
    fun provideLiteRtComposeLlmGate(): LiteRtComposeLlmGate = LiteRtComposeLlmGate()

    @Provides
    fun provideConnectivityRepository(context: Context): ConnectivityRepository = ConnectivityRepository(context)

    @Provides
    fun provideSetupRepository(
        context: Context,
        connectivityRepository: ConnectivityRepository
    ): SetupRepository = SetupRepository(
        context = context,
        connectivityRepository = connectivityRepository
    )

    @DependencyGraph.Factory
    fun interface Factory {
        fun create(@Provides application: Application): AppGraph
    }
}
