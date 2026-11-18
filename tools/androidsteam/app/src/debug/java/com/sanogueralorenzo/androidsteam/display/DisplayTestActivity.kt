package com.sanogueralorenzo.androidsteam.display

import android.app.Activity
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import com.sanogueralorenzo.androidsteam.input.SteamSurface
import com.sanogueralorenzo.androidsteam.input.InputOverlay
import com.sanogueralorenzo.androidsteam.input.TouchControls
import com.sanogueralorenzo.androidsteam.input.OnScreenControls
import com.sanogueralorenzo.androidsteam.R
import android.view.View
import android.widget.FrameLayout
import java.util.concurrent.CountDownLatch

// A real SurfaceView for the Linux display integration test; absent from release.
class DisplayTestActivity : Activity(), SurfaceHolder.Callback {
    lateinit var surface: SurfaceView
        private set
    lateinit var overlay: InputOverlay
        private set
    val ready = CountDownLatch(1)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        surface = SteamSurface(this).apply { id = R.id.surface; requestFocus() }
        surface.holder.setFixedSize(320, 200)
        surface.holder.addCallback(this)
        overlay = InputOverlay(this)
        val size = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
        overlay.addView(surface, size)
        overlay.addView(TouchControls(this).apply { id = R.id.keyboard_controls; visibility = View.GONE }, size)
        overlay.addView(OnScreenControls(this).apply { id = R.id.xbox_controls; visibility = View.GONE }, size)
        setContentView(overlay)
    }
    override fun surfaceCreated(holder: SurfaceHolder) = Unit
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { ready.countDown() }
    override fun surfaceDestroyed(holder: SurfaceHolder) = Unit
}
