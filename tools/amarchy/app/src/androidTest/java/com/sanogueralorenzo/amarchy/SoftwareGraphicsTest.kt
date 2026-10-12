package com.sanogueralorenzo.amarchy

import android.content.Intent
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.PixelCopy
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.amarchy.runtime.EnvironmentInstaller
import com.sanogueralorenzo.amarchy.runtime.LinuxRuntime
import com.sanogueralorenzo.amarchy.display.DisplayExperimentActivity
import com.sanogueralorenzo.amarchy.display.NativeDisplay
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SoftwareGraphicsTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun mesaRendersIntoAnExportedMemoryBufferWithoutGpuHardware() {
        val installer = EnvironmentInstaller(context)
        installer.prepare { _, _ -> }
        val process = LinuxRuntime(context, installer.root).start(
            listOf("/opt/amarchy/libamarchy-egl-probe.so"),
            listOf("${context.applicationInfo.nativeLibraryDir}:/opt/amarchy"),
            mapOf("LD_PRELOAD" to "/opt/amarchy/libamarchy-software-drm.so",
                "LIBGL_ALWAYS_SOFTWARE" to "1", "MESA_LOADER_DRIVER_OVERRIDE" to "kms_swrast", "GALLIUM_DRIVER" to "llvmpipe",
                "AMARCHY_DRM_TRACE" to "1", "EGL_LOG_LEVEL" to "debug"))
        try {
            assertTrue("Mesa software probe timed out", process.waitFor(30, TimeUnit.SECONDS))
            val output = process.inputStream.bufferedReader().readText()
            println(output)
            assertEquals(output, 0, process.exitValue())
            assertTrue(output, output.contains("frame-ready: 0xffff0000"))
            assertTrue(output, output.contains("llvmpipe"))
        } finally { process.destroyForcibly(); process.waitFor(5, TimeUnit.SECONDS) }
    }

    @Test fun hyprlandRendersARealTerminalAndAcceptsKeyboardInput() {
        val installer = EnvironmentInstaller(context)
        installer.prepare { _, _ -> }
        val directory = File(context.cacheDir, "hyprland-experiment").apply { mkdirs() }
        File(directory, "shm").mkdirs()
        File(directory, "foot.ini").writeText("""
            [main]
            font=DejaVu Sans Mono:size=18
            [colors-dark]
            background=1b241c
            foreground=b8eea2
        """.trimIndent() + "\n")
        File(directory, "hyprland.conf").writeText("""
            monitor = ,960x640@30,0x0,1
            exec-once = foot -c /run/amarchy/foot.ini /bin/bash --noprofile --norc
            general {
                border_size = 2
                gaps_in = 5
                gaps_out = 8
                col.active_border = rgb(b8eea2)
            }
            decoration {
                rounding = 8
                blur {
                    enabled = false
                }
            }
            animations {
                enabled = false
            }
            misc {
                disable_hyprland_logo = true
                disable_splash_rendering = true
            }
            cursor {
                no_hardware_cursors = true
            }
        """.trimIndent() + "\n")
        val socket = File(directory, "wayland-0")
        val proof = File(context.filesDir, "home/hyprproof").apply { delete() }
        val activity = instrumentation.startActivitySync(Intent(context, DisplayExperimentActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as DisplayExperimentActivity
        var process: Process? = null
        try {
            assertTrue(activity.ready.await(10, TimeUnit.SECONDS))
            NativeDisplay.start(socket.path, activity.surface.holder.surface, 30_000)
            process = LinuxRuntime(context, installer.root).start(
                listOf("/bin/bash", "-c", "exec dbus-run-session -- Hyprland --i-am-really-stupid --config /run/amarchy/hyprland.conf > /run/amarchy/session.log 2>&1"),
                listOf("${directory.path}:/run/amarchy", "${directory.path}/shm:/dev/shm", "${context.applicationInfo.nativeLibraryDir}:/opt/amarchy"),
                mapOf("XDG_RUNTIME_DIR" to "/run/amarchy", "WAYLAND_DISPLAY" to "wayland-0", "XDG_CURRENT_DESKTOP" to "Hyprland",
                    "LD_PRELOAD" to "/opt/amarchy/libamarchy-aquamarine.so:/opt/amarchy/libamarchy-software-drm.so",
                    "LIBGL_ALWAYS_SOFTWARE" to "1", "MESA_LOADER_DRIVER_OVERRIDE" to "kms_swrast", "GALLIUM_DRIVER" to "llvmpipe",
                    "AMARCHY_DRM_TRACE" to "1", "AQ_TRACE" to "1"))
            val deadline = SystemClock.elapsedRealtime() + 30_000
            while (process.isAlive && NativeDisplay.snapshot()[0] < 3 && SystemClock.elapsedRealtime() < deadline) Thread.sleep(50)
            val log = File(directory, "session.log").takeIf { it.exists() }?.readText().orEmpty()
            println(log.takeLast(30_000))
            assertTrue("Hyprland stopped: ${log.takeLast(8000)}", process.isAlive)
            assertTrue("Hyprland produced no desktop frames: ${log.takeLast(8000)}", NativeDisplay.snapshot()[0] >= 3)
            Thread.sleep(1000)
            val bitmap = Bitmap.createBitmap(960, 640, Bitmap.Config.ARGB_8888)
            val copied = CountDownLatch(1)
            var result = -1
            PixelCopy.request(activity.surface, bitmap, { result = it; copied.countDown() }, Handler(Looper.getMainLooper()))
            assertTrue(copied.await(5, TimeUnit.SECONDS)); assertEquals(PixelCopy.SUCCESS, result)
            File(context.cacheDir, "hyprland-proof.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
            for (code in listOf(20, 24, 22, 46, 35, 57, 35, 21, 25, 19, 25, 19, 24, 24, 33, 28)) {
                NativeDisplay.key(code, true); Thread.sleep(12); NativeDisplay.key(code, false); Thread.sleep(12)
            }
            val inputDeadline = SystemClock.elapsedRealtime() + 5_000
            while (!proof.exists() && process.isAlive && SystemClock.elapsedRealtime() < inputDeadline) Thread.sleep(25)
            assertTrue("Keyboard input did not reach Hyprland's real terminal", proof.exists())
            val visibleDeadline = SystemClock.elapsedRealtime() + 10_000
            var terminalPixels = 0
            do {
                val rendered = Bitmap.createBitmap(960, 640, Bitmap.Config.ARGB_8888)
                val complete = CountDownLatch(1)
                var copyResult = -1
                PixelCopy.request(activity.surface, rendered, { copyResult = it; complete.countDown() }, Handler(Looper.getMainLooper()))
                assertTrue(complete.await(5, TimeUnit.SECONDS)); assertEquals(PixelCopy.SUCCESS, copyResult)
                val pixels = IntArray(960 * 640)
                rendered.getPixels(pixels, 0, 960, 0, 0, 960, 640)
                terminalPixels = pixels.count { it == 0xff1b241c.toInt() }
                File(context.cacheDir, "hyprland-proof.png").outputStream().use { rendered.compress(Bitmap.CompressFormat.PNG, 100, it) }
                rendered.recycle()
                if (terminalPixels >= 300_000) break
                Thread.sleep(100)
            } while (SystemClock.elapsedRealtime() < visibleDeadline)
            assertTrue("Hyprland's terminal pixels never appeared ($terminalPixels matching pixels)", terminalPixels >= 300_000)
            NativeDisplay.attach(null)
            var recreated: CountDownLatch? = null
            instrumentation.runOnMainSync { recreated = activity.recreateSurface() }
            assertTrue(recreated!!.await(10, TimeUnit.SECONDS))
            NativeDisplay.attach(activity.surface.holder.surface)
            val restored = Bitmap.createBitmap(960, 640, Bitmap.Config.ARGB_8888)
            val restoredCopy = CountDownLatch(1)
            var restoredResult = -1
            PixelCopy.request(activity.surface, restored, { restoredResult = it; restoredCopy.countDown() }, Handler(Looper.getMainLooper()))
            assertTrue(restoredCopy.await(5, TimeUnit.SECONDS)); assertEquals(PixelCopy.SUCCESS, restoredResult)
            val restoredPixels = IntArray(960 * 640)
            restored.getPixels(restoredPixels, 0, 960, 0, 0, 960, 640)
            assertTrue("Desktop was blank after surface recreation", restoredPixels.count { it == 0xff1b241c.toInt() } >= 300_000)
            restored.recycle()
            assertTrue(process.isAlive)
        } finally {
            process?.destroyForcibly(); process?.waitFor(5, TimeUnit.SECONDS)
            NativeDisplay.stop()
            assertFalse(socket.exists())
            instrumentation.runOnMainSync { activity.finish() }
            proof.delete()
            // Keep diagnostics for a failed experiment; successful runs can replace them.
        }
    }
}
