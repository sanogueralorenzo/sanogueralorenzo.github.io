package com.sanogueralorenzo.amarchy.display

import android.app.Activity
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import java.util.concurrent.CountDownLatch

/** Actual Android surface for runtime experiments; excluded from release builds. */
class DisplayExperimentActivity : Activity(), SurfaceHolder.Callback {
    lateinit var surface: SurfaceView
        private set
    val ready = CountDownLatch(1)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        surface = SurfaceView(this)
        surface.holder.setFixedSize(960, 640)
        surface.holder.addCallback(this)
        setContentView(surface)
    }
    override fun surfaceCreated(holder: SurfaceHolder) = Unit
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { ready.countDown() }
    override fun surfaceDestroyed(holder: SurfaceHolder) = Unit

    fun recreateSurface(): CountDownLatch {
        val recreated = CountDownLatch(1)
        surface = SurfaceView(this)
        surface.holder.setFixedSize(960, 640)
        surface.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) = Unit
            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { recreated.countDown() }
            override fun surfaceDestroyed(holder: SurfaceHolder) = Unit
        })
        setContentView(surface)
        return recreated
    }
}
