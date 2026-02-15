package com.sanogueralorenzo.voice

import android.app.Application
import com.airbnb.mvrx.Mavericks
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.LogSeverity
import com.sanogueralorenzo.voice.di.AppGraph
import dev.zacsweers.metro.createGraphFactory

class VoiceApp : Application() {
    val appGraph: AppGraph by lazy {
        createGraphFactory<AppGraph.Factory>().create(this)
    }

    override fun onCreate() {
        super.onCreate()
        Mavericks.initialize(this)
        runCatching {
            Engine.Companion.setNativeMinLogSeverity(LogSeverity.ERROR)
        }
    }
}
