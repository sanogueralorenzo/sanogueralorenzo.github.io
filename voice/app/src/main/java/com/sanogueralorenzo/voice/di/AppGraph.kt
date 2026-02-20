package com.sanogueralorenzo.voice.di

import android.app.Application
import android.content.Context
import com.sanogueralorenzo.voice.asr.AsrRuntimeStatusStore
import com.sanogueralorenzo.voice.connectivity.ConnectivityRepository
import com.sanogueralorenzo.voice.models.ModelUpdateChecker
import com.sanogueralorenzo.voice.preferences.PreferencesRepository
import com.sanogueralorenzo.voice.theme.ThemeRepository
import com.sanogueralorenzo.voice.setup.SetupRepository
import com.sanogueralorenzo.voice.summary.ComposePreLlmRules
import com.sanogueralorenzo.voice.summary.ComposePostLlmRules
import com.sanogueralorenzo.voice.summary.SummaryEngine
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.DependencyGraph
import dev.zacsweers.metro.Provides
import dev.zacsweers.metro.SingleIn

@SingleIn(AppScope::class)
@DependencyGraph(AppScope::class)
interface AppGraph {
    val preferencesRepository: PreferencesRepository
    val themeRepository: ThemeRepository
    val asrRuntimeStatusStore: AsrRuntimeStatusStore
    val modelUpdateChecker: ModelUpdateChecker
    val composePostLlmRules: ComposePostLlmRules
    val composePreLlmRules: ComposePreLlmRules
    val summaryEngine: SummaryEngine
    val connectivityRepository: ConnectivityRepository
    val setupRepository: SetupRepository

    @Provides
    fun provideApplicationContext(application: Application): Context = application

    @Provides
    fun provideComposePostLlmRules(): ComposePostLlmRules = ComposePostLlmRules()

    @Provides
    fun provideComposePreLlmRules(): ComposePreLlmRules = ComposePreLlmRules()

    @Provides
    fun provideSummaryEngine(
        context: Context,
        composePostLlmRules: ComposePostLlmRules,
        composePreLlmRules: ComposePreLlmRules
    ): SummaryEngine = SummaryEngine(
        context = context,
        composePolicy = composePostLlmRules,
        composePreLlmRules = composePreLlmRules
    )

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
