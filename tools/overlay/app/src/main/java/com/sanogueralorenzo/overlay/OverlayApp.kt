package com.sanogueralorenzo.overlay

import android.app.Application
import com.airbnb.mvrx.Mavericks
import com.sanogueralorenzo.overlay.di.AppGraph
import dev.zacsweers.metro.createGraphFactory

class OverlayApp : Application() {
    val appGraph: AppGraph by lazy {
        createGraphFactory<AppGraph.Factory>().create(this)
    }

    override fun onCreate() {
        super.onCreate()
        Mavericks.initialize(this)
    }
}
