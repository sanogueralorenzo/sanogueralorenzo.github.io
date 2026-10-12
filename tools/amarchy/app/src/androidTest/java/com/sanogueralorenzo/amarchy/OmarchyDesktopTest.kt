package com.sanogueralorenzo.amarchy

import android.content.Intent
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.amarchy.desktop.DesktopSurface
import com.sanogueralorenzo.amarchy.session.DesktopSession
import com.sanogueralorenzo.amarchy.session.Phase
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OmarchyDesktopTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val workspace get() = (context.applicationContext as AmarchyApplication).workspace

    @Test fun upstreamShellMenusAndThemeChangesRenderAndRemainAlive() {
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val desktop = DesktopSession(context)
        try {
            instrumentation.runOnMainSync { descendants(activity.window.decorView).filterIsInstance<Button>().first { it.text == "Get started" }.performClick() }
            await(Phase.RUNNING, 90_000)
            assertEquals("ok", desktop.command(listOf("omarchy-shell", "shell", "ping")).trim())
            var surface: DesktopSurface? = null
            instrumentation.runOnMainSync { surface = descendants(activity.window.decorView).filterIsInstance<DesktopSurface>().single() }
            val initial = capture(surface!!, "omarchy-desktop")
            instrumentation.runOnMainSync { descendants(activity.window.decorView).filterIsInstance<Button>().first { it.text == "Omarchy" }.performClick() }
            assertRepaint(surface!!, initial, "omarchy-menu")
            desktop.command(listOf("omarchy-menu", "close"))
            desktop.command(listOf("omarchy-theme-set", "Everforest"), 60)
            assertEquals("everforest", File(context.filesDir, "home/.local/state/omarchy/current/theme.name").readText().trim())
            assertRepaint(surface!!, initial, "omarchy-everforest")
            desktop.command(listOf("omarchy-theme-set", "Tokyo Night"), 60)
            val stable = SystemClock.elapsedRealtime() + 30_000
            while (SystemClock.elapsedRealtime() < stable) {
                assertEquals("The upstream shell overloaded Android's process budget", Phase.RUNNING, workspace.state.phase)
                assertEquals("ok", desktop.command(listOf("omarchy-shell", "shell", "ping")).trim())
                Thread.sleep(1000)
            }
        } finally {
            instrumentation.runOnMainSync { workspace.stop() }
            await(Phase.WELCOME, 15_000)
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    private fun await(phase: Phase, timeout: Long) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (workspace.state.phase != phase && SystemClock.elapsedRealtime() < deadline) {
            if (workspace.state.phase == Phase.FAILED) fail(workspace.state.detail)
            Thread.sleep(50)
        }
        assertEquals(workspace.state.detail, phase, workspace.state.phase)
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    private fun capture(surface: DesktopSurface, name: String): IntArray {
        val image = Bitmap.createBitmap(surface.bufferWidth, surface.bufferHeight, Bitmap.Config.ARGB_8888)
        val copied = CountDownLatch(1)
        var result = -1
        PixelCopy.request(surface, image, { result = it; copied.countDown() }, Handler(Looper.getMainLooper()))
        assertTrue(copied.await(5, TimeUnit.SECONDS)); assertEquals(PixelCopy.SUCCESS, result)
        val pixels = IntArray(image.width * image.height)
        image.getPixels(pixels, 0, image.width, 0, 0, image.width, image.height)
        File(context.cacheDir, "$name.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
        image.recycle()
        return pixels
    }
    private fun assertRepaint(surface: DesktopSurface, previous: IntArray, name: String) {
        val deadline = SystemClock.elapsedRealtime() + 10_000
        do {
            val pixels = capture(surface, name)
            if (pixels.indices.count { pixels[it] != previous[it] } > 20_000) return
            Thread.sleep(100)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("$name did not become visible on the actual desktop")
    }
}
