package com.sanogueralorenzo.androiddeck

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.PixelCopy
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androiddeck.display.DisplayTestActivity
import com.sanogueralorenzo.androiddeck.display.NativeDisplay
import com.sanogueralorenzo.androiddeck.runtime.LinuxRuntime
import com.sanogueralorenzo.androiddeck.runtime.RuntimeInstaller
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DisplayIntegrationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun linuxFramesReachAndroidAndDisplayRestartsCleanly() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyDisplay") == "true")
        val runtime = RuntimeInstaller(context.filesDir, context.cacheDir)
        assertTrue("Install the runtime before the display integration test", runtime.installed)
        val activity = instrumentation.startActivitySync(Intent(context, DisplayTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as DisplayTestActivity
        val sockets = File(context.cacheDir, "display-test").apply { mkdirs() }
        val socket = File(sockets, "wayland-0")
        val linux = LinuxRuntime(context, runtime.root)
        var running: Process? = null
        try {
            assertTrue("Android surface never became ready", activity.ready.await(5, TimeUnit.SECONDS))
            assertThrows(IllegalStateException::class.java) {
                NativeDisplay.start(File(sockets, "missing/wayland-0").path, activity.surface.holder.surface, 60_000)
            }
            assertArrayEquals(longArrayOf(0, 0, 0), NativeDisplay.snapshot())
            repeat(4) { iteration ->
                val hold = iteration == 1 || iteration == 2
                var guest: File? = null
                NativeDisplay.start(socket.path, activity.surface.holder.surface, 60_000)
                assertThrows(IllegalStateException::class.java) { NativeDisplay.start(socket.path, activity.surface.holder.surface, 60_000) }
                NativeDisplay.attach(null)
                NativeDisplay.attach(activity.surface.holder.surface)
                running = linux.start(
                    listOf("/opt/androiddeck/app/libwayland-probe.so") + if (hold) listOf("hold") else emptyList(),
                    listOf("${context.applicationInfo.nativeLibraryDir}:/opt/androiddeck/app", "${sockets.path}:/run/androiddeck"),
                    mapOf("XDG_RUNTIME_DIR" to "/run/androiddeck", "WAYLAND_DISPLAY" to "wayland-0")
                )
                if (hold) {
                    val deadline = SystemClock.elapsedRealtime() + 10_000
                    while (NativeDisplay.snapshot()[0] < 3 && running!!.isAlive && SystemClock.elapsedRealtime() < deadline) Thread.sleep(10)
                    assertTrue("Client exited before the shutdown test", running!!.isAlive)
                    val line = running!!.inputStream.bufferedReader().lineSequence().first { it.startsWith("linux-wayland-ok:") }
                    guest = File("/proc/${line.substringAfter("pid=").toInt()}")
                    assertTrue("Cannot observe the live Linux child", guest.exists())
                } else {
                    assertTrue("Linux display client timed out", running!!.waitFor(20, TimeUnit.SECONDS))
                    val output = running!!.inputStream.bufferedReader().readText()
                    assertEquals(output, 0, running!!.exitValue())
                    assertTrue(output, output.contains("linux-wayland-ok: 3 frames, 320x200"))
                }
                assertArrayEquals(longArrayOf(3, 320, 200), NativeDisplay.snapshot())
                assertPixels(activity)
                NativeDisplay.stop()
                if (running!!.isAlive) {
                    if (iteration == 2) running!!.destroyForcibly() else running!!.destroy()
                    assertTrue("Cancelled Linux client was not reaped", running!!.waitFor(3, TimeUnit.SECONDS))
                }
                if (guest != null) {
                    val deadline = SystemClock.elapsedRealtime() + 3_000
                    while (guest.exists() && SystemClock.elapsedRealtime() < deadline) Thread.sleep(10)
                    assertFalse("Linux child survived its PRoot session", guest.exists())
                }
                assertFalse("Socket survived display shutdown", socket.exists())
                assertFalse("Socket lock survived display shutdown", File(sockets, "wayland-0.lock").exists())
                assertArrayEquals(longArrayOf(0, 0, 0), NativeDisplay.snapshot())
            }
        } finally {
            running?.destroyForcibly()
            running?.waitFor(3, TimeUnit.SECONDS)
            NativeDisplay.stop()
            NativeDisplay.stop() // Cleanup is also safe after a failed start or completed shutdown.
            instrumentation.runOnMainSync { activity.finish() }
            sockets.deleteRecursively()
        }
    }

    private fun assertPixels(activity: DisplayTestActivity) {
        val image = Bitmap.createBitmap(320, 200, Bitmap.Config.ARGB_8888)
        val copied = CountDownLatch(1)
        var result = -1
        try {
            PixelCopy.request(activity.surface, image, { result = it; copied.countDown() }, Handler(Looper.getMainLooper()))
            assertTrue("Pixel copy timed out", copied.await(5, TimeUnit.SECONDS))
            assertEquals("Android surface has no readable frame", PixelCopy.SUCCESS, result)
            assertEquals(Color.RED, image.getPixel(80, 50))
            assertEquals(Color.GREEN, image.getPixel(240, 50))
            assertEquals(Color.BLUE, image.getPixel(80, 150))
            assertEquals(Color.WHITE, image.getPixel(240, 150))
        } finally { image.recycle() }
    }
}
