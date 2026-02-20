package com.sanogueralorenzo.voice

import android.app.Application
import com.airbnb.mvrx.Mavericks
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.LogSeverity
import com.sanogueralorenzo.voice.di.AppGraph
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.summary.SummaryWarmup
import com.sanogueralorenzo.voice.summary.SummaryEngine
import com.sanogueralorenzo.voice.prompt.PromptTemplateStore
import dev.zacsweers.metro.createGraphFactory

class VoiceApp : Application() {
    val appGraph: AppGraph by lazy {
        createGraphFactory<AppGraph.Factory>().create(this)
    }
    private val promptTemplateStore by lazy {
        PromptTemplateStore(this)
    }
    private val liteRtWarmupSummarizer by lazy {
        SummaryEngine(
            context = this,
            composePolicy = appGraph.composePostLlmRules,
            composePreLlmRules = appGraph.composePreLlmRules
        )
    }
    private val liteRtInitializer by lazy {
        SummaryWarmup(
            isModelAvailable = { liteRtWarmupSummarizer.isModelAvailable() },
            runWarmup = { text -> liteRtWarmupSummarizer.summarizeBlocking(text) },
            modelReadyFlow = ModelStore.observeModelReady(this, ModelCatalog.liteRtLm),
            promptReadyFlow = promptTemplateStore.observePromptReady()
        )
    }

    override fun onCreate() {
        super.onCreate()
        Mavericks.initialize(this)
        runCatching {
            Engine.Companion.setNativeMinLogSeverity(LogSeverity.ERROR)
        }
        liteRtInitializer.startWarmupObservation()
    }
}
