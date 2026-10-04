package com.sanogueralorenzo.androiddeck

import android.content.Intent
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androiddeck.display.DisplayTestActivity
import com.sanogueralorenzo.androiddeck.display.GraphicsInstaller
import com.sanogueralorenzo.androiddeck.display.NativeDisplay
import com.sanogueralorenzo.androiddeck.runtime.LinuxRuntime
import com.sanogueralorenzo.androiddeck.runtime.RuntimeInstaller
import com.sanogueralorenzo.androiddeck.session.SessionComponents
import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SessionIntegrationTest {
    @Test fun componentsInstallAndExecutablesResolveTheirDependencies() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifySession") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val runtime = RuntimeInstaller(context)
        assertTrue("Install Linux first", runtime.installed)
        val components = SessionComponents(context)
        val preserved = File.createTempFile("session-validation-", ".txt", File(context.filesDir, "home"))
        try {
            preserved.writeText("keep user data")
            components.install { println(it) }
            assertEquals("keep user data", preserved.readText())
            assertTrue(components.installed)
            components.install { fail("Installed session components should not extract again") }
            assertFalse(File(context.filesDir, "session-components-staging").exists())
            assertEquals(".", Files.readSymbolicLink(File(components.root, "usr/bin/X11").toPath()).toString())
            assertFalse(File(components.root, "usr/share/gamescope/scripts/00-gamescope/common/._inspect.lua").exists())
            repeat(2) {
                val process = LinuxRuntime(context, runtime.root).start(
                    listOf("/bin/sh", "-c", "ldd /opt/androiddeck/session/usr/games/gamescope && ldd /opt/androiddeck/session/usr/bin/Xwayland && /opt/androiddeck/session/usr/games/gamescope --version && /opt/androiddeck/session/usr/bin/Xwayland -version"),
                    listOf("${components.root.path}:/opt/androiddeck/session"),
                    mapOf("LD_LIBRARY_PATH" to "/opt/androiddeck/session/usr/lib/aarch64-linux-gnu:/opt/androiddeck/session/usr/lib/aarch64-linux-gnu/pulseaudio")
                )
                try {
                    assertTrue("Session dependency check timed out", process.waitFor(20, TimeUnit.SECONDS))
                    val output = process.inputStream.bufferedReader().readText()
                    assertEquals(output, 0, process.exitValue())
                    assertFalse(output, output.contains("not found"))
                    assertTrue(output, output.contains("gamescope version 3.16.20"))
                    assertTrue(output, output.contains("Xwayland Version 24.1.10"))
                    println(output)
                } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS) }
            }
        } finally { preserved.delete() }
    }

    @Test fun gamescopeLoadsAndPresentsThroughTheNativeSurface() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifySession") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val runtime = RuntimeInstaller(context)
        val graphics = GraphicsInstaller(context)
        val components = SessionComponents(context)
        assertTrue("Install Linux and graphics first", runtime.installed && graphics.installed)
        components.install { println(it) }
        assertTrue(components.installed)
        components.install { fail("Installed session components should not extract again") }
        val activity = instrumentation.startActivitySync(Intent(context, DisplayTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as DisplayTestActivity
        val sockets = File(context.cacheDir, "session-test").apply { mkdirs() }
        val socket = File(sockets, "wayland-0")
        val log = File(context.cacheDir, "session-test.log")
        var process: Process? = null
        var reader: Thread? = null
        try {
            assertTrue(activity.ready.await(5, TimeUnit.SECONDS))
            NativeDisplay.startVulkan(socket.path, activity.surface.holder.surface, 60_000,
                File(graphics.root, "android").path, context.applicationInfo.nativeLibraryDir)
            process = LinuxRuntime(context, runtime.root).start(
                listOf("/opt/androiddeck/session/usr/games/gamescope", "--backend", "sdl", "--expose-wayland", "-W", "320", "-H", "200", "--", "/opt/androiddeck/app/libwayland-vulkan-probe.so"),
                listOf("${components.root.path}:/opt/androiddeck/session", "${graphics.root.path}:/opt/androiddeck/graphics",
                    "${context.applicationInfo.nativeLibraryDir}:/opt/androiddeck/app", "${sockets.path}:/run/androiddeck",
                    "${components.root.path}/usr/share/gamescope:/usr/share/gamescope"),
                mapOf("XDG_RUNTIME_DIR" to "/run/androiddeck", "WAYLAND_DISPLAY" to "wayland-0", "SDL_VIDEODRIVER" to "wayland", "WAYLAND_DEBUG" to "client",
                    "PATH" to "/opt/androiddeck/session/usr/bin:/usr/bin:/bin",
                    "LD_LIBRARY_PATH" to "/opt/androiddeck/session/usr/lib/aarch64-linux-gnu:/opt/androiddeck/session/usr/lib/aarch64-linux-gnu/pulseaudio:/opt/androiddeck/graphics/usr/lib/aarch64-linux-gnu",
                    "VK_DRIVER_FILES" to "/opt/androiddeck/graphics/linux/freedreno_icd.aarch64.json")
            )
            val running = process
            reader = Thread { log.outputStream().use { output -> running.inputStream.use { it.copyTo(output) } } }.apply { start() }
            val deadline = SystemClock.elapsedRealtime() + 30_000
            while (running.isAlive && NativeDisplay.snapshot()[0] == 0L && SystemClock.elapsedRealtime() < deadline) Thread.sleep(20)
            val output = log.takeIf { it.isFile }?.readText().orEmpty()
            println("Gamescope startup:\n$output")
            assertTrue("Gamescope did not present a frame:\n$output", NativeDisplay.snapshot()[0] > 0)
        } finally {
            process?.destroy()
            if (process?.waitFor(3, TimeUnit.SECONDS) == false) { process?.destroyForcibly(); process?.waitFor(3, TimeUnit.SECONDS) }
            reader?.join(3_000)
            NativeDisplay.stop()
            instrumentation.runOnMainSync { activity.finish() }
            sockets.deleteRecursively()
        }
    }
}
