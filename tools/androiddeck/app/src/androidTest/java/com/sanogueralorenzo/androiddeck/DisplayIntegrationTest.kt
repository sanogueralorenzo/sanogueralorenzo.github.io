package com.sanogueralorenzo.androiddeck

import android.content.Intent
import android.graphics.Color
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androiddeck.display.DisplayTestActivity
import com.sanogueralorenzo.androiddeck.display.NativeDisplay
import com.sanogueralorenzo.androiddeck.display.GraphicsInstaller
import com.sanogueralorenzo.androiddeck.runtime.LinuxRuntime
import com.sanogueralorenzo.androiddeck.runtime.RuntimeInstaller
import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DisplayIntegrationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun unsupportedGpuDoesNotLeaveADisplayOrPreventRestart() {
        assumeTrue("Requires a device without accessible Adreno hardware", !File("/dev/kgsl-3d0").canRead())
        val activity = instrumentation.startActivitySync(Intent(context, DisplayTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as DisplayTestActivity
        val sockets = File(context.cacheDir, "unsupported-gpu-test").apply { mkdirs() }
        val socket = File(sockets, "wayland-0")
        try {
            assertTrue(activity.ready.await(5, TimeUnit.SECONDS))
            repeat(3) {
                val failure = assertThrows(IllegalStateException::class.java) {
                    NativeDisplay.startVulkan(socket.path, activity.surface.holder.surface, 60_000,
                        File(context.filesDir, "graphics/android").path, context.applicationInfo.nativeLibraryDir)
                }
                assertTrue(failure.message, failure.message.orEmpty().contains("Adreno GPU is required"))
                assertFalse(socket.exists())
                assertFalse(File(sockets, "wayland-0.lock").exists())
                assertArrayEquals(longArrayOf(0, 0, 0), NativeDisplay.snapshot())
                NativeDisplay.stop()
            }
            NativeDisplay.start(socket.path, activity.surface.holder.surface, 60_000)
            assertTrue(socket.exists())
            NativeDisplay.stop()
            assertFalse(socket.exists())
        } finally {
            NativeDisplay.stop()
            instrumentation.runOnMainSync { activity.finish() }
            sockets.deleteRecursively()
        }
    }

    @Test fun linuxVulkanFramesReachTheAdrenoSurfaceAndRestart() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyVulkan") == "true")
        assertTrue("Connect the supported Adreno device for this test", File("/dev/kgsl-3d0").canRead())
        val runtime = RuntimeInstaller(context)
        val graphics = GraphicsInstaller(context)
        assertTrue("Install the Linux runtime first", runtime.installed)
        graphics.install { println(it) }
        assertTrue("The matched graphics pair did not install", graphics.installed)
        val activity = instrumentation.startActivitySync(Intent(context, DisplayTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as DisplayTestActivity
        val sockets = File(context.cacheDir, "vulkan-test").apply { mkdirs() }
        val socket = File(sockets, "wayland-0")
        var running: Process? = null
        try {
            assertTrue(activity.ready.await(5, TimeUnit.SECONDS))
            repeat(2) {
                NativeDisplay.startVulkan(socket.path, activity.surface.holder.surface, 60_000,
                    File(graphics.root, "android").path, context.applicationInfo.nativeLibraryDir)
                NativeDisplay.attach(null)
                NativeDisplay.attach(activity.surface.holder.surface)
                running = LinuxRuntime(context, runtime.root).start(
                    listOf("/opt/androiddeck/app/libwayland-vulkan-probe.so"),
                    listOf("${context.applicationInfo.nativeLibraryDir}:/opt/androiddeck/app",
                        "${graphics.root.path}:/opt/androiddeck/graphics", "${sockets.path}:/run/androiddeck"),
                    mapOf("XDG_RUNTIME_DIR" to "/run/androiddeck", "WAYLAND_DISPLAY" to "wayland-0",
                        "LD_LIBRARY_PATH" to "/opt/androiddeck/graphics/usr/lib/aarch64-linux-gnu",
                        "VK_DRIVER_FILES" to "/opt/androiddeck/graphics/linux/freedreno_icd.aarch64.json")
                )
                assertTrue("Linux Vulkan client timed out", running!!.waitFor(20, TimeUnit.SECONDS))
                val output = running!!.inputStream.bufferedReader().readText()
                println(output)
                assertEquals(output, 0, running!!.exitValue())
                assertTrue(output, output.contains("linux-vulkan-ok: 3 frames, 320x200"))
                assertTrue(output, output.contains("linux-presentation-ok: 3 ordered display timestamps"))
                assertArrayEquals(longArrayOf(3, 320, 200), NativeDisplay.snapshot())
                DisplayPixels.awaitBlue(activity)
                NativeDisplay.stop()
                assertFalse(socket.exists())
                assertFalse(File(sockets, "wayland-0.lock").exists())
            }
        } finally {
            running?.destroyForcibly()
            running?.waitFor(3, TimeUnit.SECONDS)
            NativeDisplay.stop()
            instrumentation.runOnMainSync { activity.finish() }
            sockets.deleteRecursively()
        }
    }

    @Test fun linuxFramesReachAndroidAndDisplayRestartsCleanly() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyDisplay") == "true")
        val runtime = RuntimeInstaller(context)
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
                DisplayPixels.withPixels(activity) { image ->
                    assertEquals(Color.RED, image.getPixel(80, 50))
                    assertEquals(Color.GREEN, image.getPixel(240, 50))
                    assertEquals(Color.BLUE, image.getPixel(80, 150))
                    assertEquals(Color.WHITE, image.getPixel(240, 150))
                }
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

}
