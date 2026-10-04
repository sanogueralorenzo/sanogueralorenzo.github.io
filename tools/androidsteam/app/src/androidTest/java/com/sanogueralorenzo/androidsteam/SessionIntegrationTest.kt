package com.sanogueralorenzo.androidsteam

import android.content.Intent
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.display.DisplayTestActivity
import com.sanogueralorenzo.androidsteam.display.GraphicsInstaller
import com.sanogueralorenzo.androidsteam.display.NativeDisplay
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import com.sanogueralorenzo.androidsteam.session.SessionComponents
import com.sanogueralorenzo.androidsteam.session.SessionRuntime
import com.sanogueralorenzo.androidsteam.session.SessionActivity
import com.sanogueralorenzo.androidsteam.session.SessionController
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SessionIntegrationTest {
    @Test fun steamSurvivesSteamGuardAndStopsCleanly() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifySteam") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, android.Manifest.permission.POST_NOTIFICATIONS)
        val session = (context.applicationContext as SteamApplication).session
        val activity = instrumentation.startActivitySync(Intent(context, SessionActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as SessionActivity
        fun await(message: String, condition: () -> Boolean) {
            val deadline = SystemClock.elapsedRealtime() + 90_000
            while (!condition() && SystemClock.elapsedRealtime() < deadline) Thread.sleep(20)
            assertTrue(message, condition())
        }
        try {
            await("Steam did not start: ${session.state}") { session.state == SessionController.State.Running || session.state is SessionController.State.Failed }
            assertEquals(SessionController.State.Running, session.state)
            instrumentation.uiAutomation.executeShellCommand("input keyevent 3").close()
            await("Steam's surface stayed attached in the background") { !activity.findViewById<android.view.SurfaceView>(R.id.surface).holder.surface.isValid }
            Thread.sleep(250)
            val hiddenFrames = NativeDisplay.snapshot()[0]
            Thread.sleep(1_000)
            assertEquals("Background frames continued presenting", hiddenFrames, NativeDisplay.snapshot()[0])
            assertEquals("Steam stopped while switching apps", SessionController.State.Running, session.state)
            context.startActivity(Intent(context, SessionActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
            await("Steam did not resume on the same display") { NativeDisplay.snapshot()[0] > hiddenFrames }
            assertEquals(SessionController.State.Running, session.state)
        } finally {
            instrumentation.runOnMainSync { session.stop(); activity.finish() }
            await("Steam did not finish stopping") { session.state == SessionController.State.Idle }
        }
        assertArrayEquals(longArrayOf(0, 0, 0), NativeDisplay.snapshot())
    }

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
                    listOf("/bin/sh", "-c", "ldd /opt/androidsteam/session/usr/games/gamescope && ldd /opt/androidsteam/session/usr/bin/Xwayland && /opt/androidsteam/session/usr/games/gamescope --version && /opt/androidsteam/session/usr/bin/Xwayland -version"),
                    listOf("${components.root.path}:/opt/androidsteam/session"),
                    mapOf("LD_LIBRARY_PATH" to "/opt/androidsteam/session/usr/lib/aarch64-linux-gnu:/opt/androidsteam/session/usr/lib/aarch64-linux-gnu/pulseaudio")
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
        repeat(2) {
            val activity = instrumentation.startActivitySync(Intent(context, DisplayTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as DisplayTestActivity
            val sockets = File(context.cacheDir, "session-test").apply { mkdirs() }
            val socket = File(sockets, "wayland-0")
            val log = File(context.cacheDir, "session-test.log")
            log.writeText("")
            var process: Process? = null
            var reader: Thread? = null
            val stopping = AtomicBoolean()
            val readFailure = AtomicReference<IOException?>()
            try {
                assertTrue(activity.ready.await(5, TimeUnit.SECONDS))
                NativeDisplay.startVulkan(socket.path, activity.surface.holder.surface, 60_000,
                    File(graphics.root, "android").path, context.applicationInfo.nativeLibraryDir)
                process = SessionRuntime(context, sockets).start(
                listOf("/bin/sh", "-c", "/opt/androidsteam/app/libx11-locale-probe.so && exec /opt/androidsteam/app/libwayland-vulkan-probe.so nested"), 320, 200)
            val running = process
                reader = Thread {
                    try { log.outputStream().use { output -> running.inputStream.use { it.copyTo(output) } } }
                    catch (failure: IOException) { if (!stopping.get()) readFailure.set(failure) }
                }.apply { start() }
                val deadline = SystemClock.elapsedRealtime() + 30_000
                while (running.isAlive && !log.readText().contains("linux-vulkan-ok") && SystemClock.elapsedRealtime() < deadline) Thread.sleep(20)
                val output = log.takeIf { it.isFile }?.readText().orEmpty()
                println("Gamescope startup:\n$output")
                assertNull("Gamescope output read failed", readFailure.get())
                assertTrue("The Linux client did not render through Gamescope:\n$output", output.contains("linux-vulkan-ok"))
                assertTrue("Gamescope did not present a frame:\n$output", NativeDisplay.snapshot()[0] > 0)
                DisplayPixels.awaitBlue(activity)
            } finally {
                stopping.set(true)
                process?.destroy()
                if (process?.waitFor(3, TimeUnit.SECONDS) == false) { process?.destroyForcibly(); process?.waitFor(3, TimeUnit.SECONDS) }
                reader?.join(3_000)
                NativeDisplay.stop()
                instrumentation.runOnMainSync { activity.finish() }
                sockets.deleteRecursively()
            }
        }
    }
}
