package com.sanogueralorenzo.amarchy

import android.content.Intent
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.Button
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.amarchy.desktop.DesktopSurface
import com.sanogueralorenzo.amarchy.session.Phase
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DesktopLifecycleTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val workspace get() = (context.applicationContext as AmarchyApplication).workspace

    @Test fun oneActionOpensDesktopAndPreservesItAcrossBackgroundStopAndRelaunch() {
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val homeProof = File(context.filesDir, "home/app-persistence-proof").apply { parentFile!!.mkdirs(); writeText("keep") }
        val inputProof = File(context.filesDir, "home/app-input-proof").apply { delete() }
        try {
            instrumentation.runOnMainSync { descendants(activity.window.decorView).filterIsInstance<Button>().first { it.text == "Get started" }.performClick() }
            awaitPhase(Phase.RUNNING, 900_000)
            var surface: DesktopSurface? = null
            instrumentation.runOnMainSync { surface = descendants(activity.window.decorView).filterIsInstance<DesktopSurface>().single() }
            assertTerminalPixels(surface!!)
            instrumentation.runOnMainSync {
                surface!!.onCreateInputConnection(EditorInfo()).commitText("printf 'café 你好\\n' > /root/app-input-proof\n", 1)
            }
            val typedDeadline = SystemClock.elapsedRealtime() + 10_000
            while (!inputProof.exists() && SystemClock.elapsedRealtime() < typedDeadline) Thread.sleep(50)
            assertTrue("Android's keyboard text did not reach the Linux terminal", inputProof.exists())
            assertEquals("café 你好\n", inputProof.readText())
            val signature = File(context.cacheDir, "s/hypr").listFiles()!!.single { it.isDirectory }.name
            instrumentation.runOnMainSync { activity.moveTaskToBack(true) }
            Thread.sleep(500)
            assertEquals(Phase.RUNNING, workspace.state.phase)
            instrumentation.runOnMainSync { activity.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)) }
            instrumentation.waitForIdleSync()
            val resumed = SystemClock.elapsedRealtime() + 10_000
            while (!activity.hasWindowFocus() && SystemClock.elapsedRealtime() < resumed) Thread.sleep(25)
            assertTrue("Desktop did not return to the foreground", activity.hasWindowFocus())
            assertEquals(signature, File(context.cacheDir, "s/hypr").listFiles()!!.single { it.isDirectory }.name)
            instrumentation.runOnMainSync { surface = descendants(activity.window.decorView).filterIsInstance<DesktopSurface>().single() }
            assertTerminalPixels(surface!!)
            instrumentation.runOnMainSync { workspace.stop() }
            awaitPhase(Phase.WELCOME, 15_000)
            assertFalse("Display socket survived stop", File(context.cacheDir, "s/wayland-0").exists())
            assertEquals("keep", homeProof.readText())
            instrumentation.runOnMainSync { descendants(activity.window.decorView).filterIsInstance<Button>().first { it.text == "Get started" }.performClick() }
            awaitPhase(Phase.RUNNING, 90_000)
            assertEquals("keep", homeProof.readText())
            assertNotEquals(signature, File(context.cacheDir, "s/hypr").listFiles()!!.single { it.isDirectory }.name)
        } finally {
            instrumentation.runOnMainSync { workspace.stop() }
            awaitPhase(Phase.WELCOME, 15_000)
            homeProof.delete(); inputProof.delete()
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    private fun awaitPhase(phase: Phase, timeout: Long) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        var previous: Phase? = null
        while (workspace.state.phase != phase && SystemClock.elapsedRealtime() < deadline) {
            if (workspace.state.phase != previous) { println("workspace: ${workspace.state.phase}: ${workspace.state.detail}"); previous = workspace.state.phase }
            if (workspace.state.phase == Phase.FAILED) fail(workspace.state.detail)
            Thread.sleep(100)
        }
        assertEquals(workspace.state.detail, phase, workspace.state.phase)
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    private fun assertTerminalPixels(surface: DesktopSurface) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        var count = 0
        do {
            val image = Bitmap.createBitmap(1280, 720, Bitmap.Config.ARGB_8888)
            val copied = CountDownLatch(1)
            var result = -1
            PixelCopy.request(surface, image, { result = it; copied.countDown() }, Handler(Looper.getMainLooper()))
            assertTrue(copied.await(5, TimeUnit.SECONDS)); assertEquals(PixelCopy.SUCCESS, result)
            val pixels = IntArray(1280 * 720)
            image.getPixels(pixels, 0, 1280, 0, 0, 1280, 720)
            count = pixels.count { it == 0xff2d353b.toInt() }
            File(context.cacheDir, "desktop-app-proof.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
            image.recycle()
            if (count >= 400_000) return
            Thread.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("The real terminal never became visible ($count pixels)")
    }
}
