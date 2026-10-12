package com.sanogueralorenzo.amarchy

import android.content.Intent
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.inputmethod.EditorInfo
import android.widget.Button
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.amarchy.desktop.DesktopSurface
import com.sanogueralorenzo.amarchy.display.NativeDisplay
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
            assertViewportFits(surface!!)
            instrumentation.runOnMainSync {
                surface!!.onCreateInputConnection(EditorInfo()).commitText("printf 'café 你好\\n' > /root/app-input-proof\n", 1)
            }
            val typedDeadline = SystemClock.elapsedRealtime() + 10_000
            while (!inputProof.exists() && SystemClock.elapsedRealtime() < typedDeadline) Thread.sleep(50)
            assertTrue("Android's keyboard text did not reach the Linux terminal", inputProof.exists())
            assertEquals("café 你好\n", inputProof.readText())
            val fullHeight = NativeDisplay.snapshot()[2]
            instrumentation.runOnMainSync { descendants(activity.window.decorView).filterIsInstance<Button>().first { it.text == "Keyboard" }.performClick() }
            val keyboardDeadline = SystemClock.elapsedRealtime() + 10_000
            while (surface!!.rootWindowInsets?.isVisible(WindowInsets.Type.ime()) != true && SystemClock.elapsedRealtime() < keyboardDeadline) Thread.sleep(50)
            assertTrue("Android keyboard did not open", surface!!.rootWindowInsets.isVisible(WindowInsets.Type.ime()))
            val resized = SystemClock.elapsedRealtime() + 10_000
            while (NativeDisplay.snapshot()[2] != surface!!.bufferHeight.toLong() && SystemClock.elapsedRealtime() < resized) Thread.sleep(50)
            assertEquals(surface!!.bufferWidth.toLong(), NativeDisplay.snapshot()[1])
            assertEquals("Hyprland did not follow the keyboard viewport", surface!!.bufferHeight.toLong(), NativeDisplay.snapshot()[2])
            assertTrue("Keyboard shrank the whole desktop instead of resizing its height", NativeDisplay.snapshot()[2] < fullHeight)
            assertTerminalPixels(surface!!)
            assertViewportFits(surface!!)
            instrumentation.runOnMainSync { surface!!.onCreateInputConnection(EditorInfo()).commitText("printf 'keyboard resized\\n' > /root/app-input-proof\n", 1) }
            val afterResize = SystemClock.elapsedRealtime() + 10_000
            while (inputProof.readText() != "keyboard resized\n" && SystemClock.elapsedRealtime() < afterResize) Thread.sleep(50)
            assertEquals("keyboard resized\n", inputProof.readText())
            instrumentation.runOnMainSync { descendants(activity.window.decorView).filterIsInstance<Button>().first { it.text == "Hide keyboard" }.performClick() }
            val restored = SystemClock.elapsedRealtime() + 10_000
            while (NativeDisplay.snapshot()[2] != fullHeight && SystemClock.elapsedRealtime() < restored) Thread.sleep(50)
            assertEquals("Desktop height did not return after hiding the keyboard", fullHeight, NativeDisplay.snapshot()[2])
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
    private fun assertViewportFits(surface: DesktopSurface) {
        val monitors = org.json.JSONArray(com.sanogueralorenzo.amarchy.session.DesktopSession(context).command(listOf("/usr/bin/hyprctl", "-j", "monitors")))
        assertEquals("Desktop scale changed while resizing", 1.5, monitors.getJSONObject(0).getDouble("scale"), 0.001)
        val deadline = SystemClock.elapsedRealtime() + 10_000
        var edges = emptyList<Boolean>()
        do {
            val image = instrumentation.uiAutomation.takeScreenshot()
            val location = IntArray(2)
            instrumentation.runOnMainSync { surface.getLocationOnScreen(location) }
            val middle = location[1] + surface.height / 2
            fun border(x: Int): Boolean {
                val pixel = image.getPixel(location[0] + x, middle)
                return kotlin.math.abs(android.graphics.Color.red(pixel) - 127) < 12 &&
                    kotlin.math.abs(android.graphics.Color.green(pixel) - 187) < 12 &&
                    kotlin.math.abs(android.graphics.Color.blue(pixel) - 179) < 12
            }
            fun horizontalBorder(y: Int): Boolean {
                val pixel = image.getPixel(location[0] + surface.width / 2, location[1] + y)
                return kotlin.math.abs(android.graphics.Color.red(pixel) - 127) < 12 &&
                    kotlin.math.abs(android.graphics.Color.green(pixel) - 187) < 12 &&
                    kotlin.math.abs(android.graphics.Color.blue(pixel) - 179) < 12
            }
            File(context.cacheDir, "desktop-viewport-${surface.bufferHeight}.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
            edges = listOf((0 until surface.width / 10).any(::border), (surface.width * 9 / 10 until surface.width).any(::border),
                (0 until surface.height / 10).any(::horizontalBorder), (surface.height * 9 / 10 until surface.height).any(::horizontalBorder))
            image.recycle()
            if (edges.all { it }) return
            Thread.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Desktop edges were cropped (left/right/top/bottom): $edges")
    }
    private fun assertTerminalPixels(surface: DesktopSurface) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        var count = 0
        do {
            val width = surface.bufferWidth
            val height = surface.bufferHeight
            val image = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val copied = CountDownLatch(1)
            var result = -1
            PixelCopy.request(surface, image, { result = it; copied.countDown() }, Handler(Looper.getMainLooper()))
            assertTrue(copied.await(5, TimeUnit.SECONDS)); assertEquals(PixelCopy.SUCCESS, result)
            val pixels = IntArray(width * height)
            image.getPixels(pixels, 0, width, 0, 0, width, height)
            count = pixels.count { it == 0xff2d353b.toInt() }
            File(context.cacheDir, "desktop-app-proof.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
            image.recycle()
            if (count >= width * height * 0.5) return
            Thread.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("The real terminal never became visible ($count pixels)")
    }
}
