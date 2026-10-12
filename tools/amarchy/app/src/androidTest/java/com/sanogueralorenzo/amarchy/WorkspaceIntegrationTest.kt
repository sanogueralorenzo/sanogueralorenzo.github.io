package com.sanogueralorenzo.amarchy

import android.content.Intent
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.PixelCopy
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.amarchy.display.DisplayExperimentActivity
import com.sanogueralorenzo.amarchy.display.NativeDisplay
import com.sanogueralorenzo.amarchy.runtime.EnvironmentInstaller
import com.sanogueralorenzo.amarchy.runtime.LinuxRuntime
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WorkspaceIntegrationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun cancelledReplacementPreservesThePreviousEnvironment() {
        val directory = File(context.filesDir, "recovery-experiment").apply { mkdirs() }
        val root = File(directory, "environment")
        val previous = File(directory, "environment-previous").apply { mkdirs() }
        File(previous, "preserved").writeText("original")
        try {
            val installer = EnvironmentInstaller(context, root)
            assertEquals("original", File(root, "preserved").readText())
            assertFalse(previous.exists())
            assertThrows(CancellationException::class.java) {
                installer.prepare { detail, progress ->
                    if (detail == "Making room for your desktop" && progress >= 0.1f) throw CancellationException()
                }
            }
            assertEquals("original", File(root, "preserved").readText())
            assertFalse("Cancelled extraction survived", File(directory, "environment-staging").exists())
        } finally { directory.deleteRecursively() }
    }

    @Test fun installsAndRunsArm64LinuxWhilePreservingHome() {
        val installer = EnvironmentInstaller(context)
        installer.prepare { detail, progress -> println("$detail ${(progress * 100).toInt()}%") }
        assertTrue(installer.installed)
        val marker = File(context.filesDir, "home/amarchy-persistence-proof").apply { parentFile!!.mkdirs(); writeText("preserved") }
        try {
            installer.prepare { _, _ -> fail("Installed runtime was prepared twice") }
            val process = LinuxRuntime(context, installer.root).start(listOf("/bin/bash", "-c", "printf 'linux-ok '; uname -m; cat /root/amarchy-persistence-proof; mkdir -p /tmp/amarchy-cli; chmod 700 /tmp/amarchy-cli; XDG_RUNTIME_DIR=/tmp/amarchy-cli Hyprland --version"))
            try {
                assertTrue("Linux command timed out", process.waitFor(30, TimeUnit.SECONDS))
                val output = process.inputStream.bufferedReader().readText()
                println(output)
                assertEquals(output, 0, process.exitValue())
                assertTrue(output, output.contains("linux-ok aarch64"))
                assertTrue(output, output.contains("preserved"))
                assertTrue(output, output.contains("Hyprland"))
            } finally { process.destroyForcibly() }
        } finally { marker.delete() }
    }

    @Test fun referenceCompositorRendersARealTerminalThroughAndroid() {
        val installer = EnvironmentInstaller(context)
        installer.prepare { _, _ -> }
        val activity = instrumentation.startActivitySync(Intent(context, DisplayExperimentActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as DisplayExperimentActivity
        val directory = File(context.cacheDir, "display-experiment").apply { mkdirs() }
        File(directory, "shm").mkdirs()
        val socket = File(directory, "wayland-0")
        val environment = mapOf("XDG_RUNTIME_DIR" to "/run/amarchy", "WAYLAND_DISPLAY" to "wayland-0", "LANG" to "C.UTF-8",
            "LD_PRELOAD" to "/opt/amarchy/libamarchy-memory.so")
        val bindings = listOf("${directory.path}:/run/amarchy", "${directory.path}/shm:/dev/shm", "${context.applicationInfo.nativeLibraryDir}:/opt/amarchy")
        var compositor: Process? = null
        var terminal: Process? = null
        val inputProof = File(context.filesDir, "home/proof").apply { delete() }
        try {
            assertTrue(activity.ready.await(10, TimeUnit.SECONDS))
            NativeDisplay.start(socket.path, activity.surface.holder.surface, 60_000)
            compositor = LinuxRuntime(context, installer.root).start(
                listOf("/bin/bash", "-c", "exec weston -B wayland --renderer=pixman --shell=kiosk-shell.so --socket=desktop-0 --width=960 --height=640 --no-config > /run/amarchy/weston.log 2>&1"),
                bindings, environment)
            val deadline = SystemClock.elapsedRealtime() + 20_000
            while (!File(directory, "desktop-0").exists() && compositor.isAlive && SystemClock.elapsedRealtime() < deadline) Thread.sleep(50)
            assertTrue(File(directory, "weston.log").takeIf { it.exists() }?.readText(), File(directory, "desktop-0").exists())
            terminal = LinuxRuntime(context, installer.root).start(
                listOf("/bin/bash", "-c", "exec foot --font='DejaVu Sans Mono:size=18' /bin/bash --noprofile --norc > /run/amarchy/foot.log 2>&1"),
                bindings, environment + ("WAYLAND_DISPLAY" to "desktop-0"))
            val renderDeadline = SystemClock.elapsedRealtime() + 15_000
            while (NativeDisplay.snapshot()[0] < 3 && terminal.isAlive && SystemClock.elapsedRealtime() < renderDeadline) Thread.sleep(50)
            println(File(directory, "weston.log").readText())
            println(File(directory, "foot.log").readText())
            assertTrue("The Linux terminal exited", terminal.isAlive)
            assertTrue("No desktop frames reached Android", NativeDisplay.snapshot()[0] >= 3)
            val bitmap = Bitmap.createBitmap(960, 640, Bitmap.Config.ARGB_8888)
            val copied = CountDownLatch(1)
            var result = -1
            PixelCopy.request(activity.surface, bitmap, { result = it; copied.countDown() }, Handler(Looper.getMainLooper()))
            assertTrue(copied.await(5, TimeUnit.SECONDS))
            assertEquals(PixelCopy.SUCCESS, result)
            val pixels = IntArray(960 * 640)
            bitmap.getPixels(pixels, 0, 960, 0, 0, 960, 640)
            assertTrue("Terminal frame is blank", pixels.toSet().size > 10)
            File(context.cacheDir, "terminal-proof.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
            // Exercise the complete Android -> host Wayland -> nested compositor -> bash path.
            for (code in listOf(20, 24, 22, 46, 35, 57, 25, 19, 24, 24, 33, 28)) {
                NativeDisplay.key(code, true); Thread.sleep(12)
                NativeDisplay.key(code, false); Thread.sleep(12)
            }
            val inputDeadline = SystemClock.elapsedRealtime() + 5_000
            while (!inputProof.exists() && terminal.isAlive && SystemClock.elapsedRealtime() < inputDeadline) Thread.sleep(25)
            assertTrue("Keyboard input did not reach the real Linux shell", inputProof.exists())
            NativeDisplay.attach(null)
            NativeDisplay.attach(activity.surface.holder.surface)
            assertTrue("Terminal did not survive surface reattachment", terminal.isAlive)
        } finally {
            terminal?.destroyForcibly(); terminal?.waitFor(5, TimeUnit.SECONDS)
            compositor?.destroyForcibly(); compositor?.waitFor(5, TimeUnit.SECONDS)
            NativeDisplay.stop()
            assertFalse("Wayland socket survived stop", socket.exists())
            instrumentation.runOnMainSync { activity.finish() }
            inputProof.delete()
            directory.deleteRecursively()
        }
    }
}
