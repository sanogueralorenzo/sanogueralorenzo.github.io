package com.sanogueralorenzo.androiddeck.display

import android.app.Activity
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import java.util.concurrent.CountDownLatch

// A real SurfaceView for the Linux display integration test; absent from release.
class DisplayTestActivity : Activity(), SurfaceHolder.Callback {
    lateinit var surface: SurfaceView
        private set
    val ready = CountDownLatch(1)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        surface = SurfaceView(this)
        surface.holder.setFixedSize(320, 200)
        surface.holder.addCallback(this)
        setContentView(surface)
    }
    override fun surfaceCreated(holder: SurfaceHolder) = Unit
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { ready.countDown() }
    override fun surfaceDestroyed(holder: SurfaceHolder) = Unit
}
