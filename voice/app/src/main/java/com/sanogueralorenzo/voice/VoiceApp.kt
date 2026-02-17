package com.sanogueralorenzo.voice

import android.app.Application
import com.airbnb.mvrx.Mavericks
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.LogSeverity
import com.sanogueralorenzo.voice.di.AppGraph
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.summary.LiteRtInitializer
import com.sanogueralorenzo.voice.summary.LiteRtSummarizer
import dev.zacsweers.metro.createGraphFactory

class VoiceApp : Application() {
    val appGraph: AppGraph by lazy {
        createGraphFactory<AppGraph.Factory>().create(this)
    }
    private val liteRtInitializer by lazy {
        LiteRtInitializer(
            summarizer = LiteRtSummarizer(this),
            modelReadyFlow = ModelStore.observeModelReady(this, ModelCatalog.liteRtLm)
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
