package com.sanogueralorenzo.androidsteam

import android.content.Intent
import android.os.SystemClock
import android.system.Os
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.audio.SessionAudio
import com.sanogueralorenzo.androidsteam.display.DisplayTestActivity
import com.sanogueralorenzo.androidsteam.display.GraphicsInstaller
import com.sanogueralorenzo.androidsteam.display.NativeDisplay
import com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive
import com.sanogueralorenzo.androidsteam.session.SessionController
import com.sanogueralorenzo.androidsteam.session.SessionRuntime
import com.sanogueralorenzo.androidsteam.login.SteamClientBridge
import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Capability proof only: no account credentials, token retrieval or authentication changes. */
@RunWith(AndroidJUnit4::class)
class SteamAuthTransportTest {
    @Test fun remoteAndParserErrorsDoNotExposePrivateValues() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        repeat(2) { variant ->
            val directory = File(context.cacheDir, "bridge-error-$variant")
            assertFalse(directory.exists())
            assertTrue(directory.mkdirs())
            val bridge = SteamClientBridge(directory)
            val sensitive = java.util.UUID.randomUUID().toString()
            val flags = android.system.OsConstants.O_RDWR or android.system.OsConstants.O_NONBLOCK or android.system.OsConstants.O_CLOEXEC
            val command = Os.open(File(directory, "ui-command").path, flags, 0)
            val response = Os.open(File(directory, "ui-response").path, flags, 0)
            val reply = Thread {
                val poll = android.system.StructPollfd().apply { fd = command; events = android.system.OsConstants.POLLIN.toShort() }
                if (Os.poll(arrayOf(poll), 5000) > 0) {
                    val buffer = ByteArray(4096)
                    Os.read(command, buffer, 0, buffer.size)
                    val packet = org.json.JSONObject().put("id", 1)
                    if (variant == 0) packet.put("error", org.json.JSONObject().put("message", sensitive))
                    else packet.put("result", org.json.JSONObject().put("targetInfos", sensitive))
                    val bytes = (packet.toString() + '\u0000').toByteArray()
                    Os.write(response, bytes, 0, bytes.size)
                }
            }
            try {
                reply.start()
                try { bridge.hasClientInterface(); fail("Malformed remote response must fail") }
                catch (failure: IllegalStateException) {
                    assertFalse("Remote values must not reach the error message", failure.message.orEmpty().contains(sensitive))
                    assertTrue("Remote errors must not escape through causes", failure.cause == null)
                }
            } finally {
                reply.join(6000)
                bridge.close(); Os.close(command); Os.close(response)
                RuntimeArchive.delete(directory)
            }
        }
    }

    @Test fun normalSessionOwnsAndClosesPrivateBridge() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyAuthTransport") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val app = context.applicationContext as SteamApplication
        assertEquals(SessionController.State.Idle, app.session.state)
        app.preparation.install { }
        val activity = instrumentation.startActivitySync(Intent(context, com.sanogueralorenzo.androidsteam.session.SessionActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as com.sanogueralorenzo.androidsteam.session.SessionActivity
        try {
            val deadline = SystemClock.elapsedRealtime() + 90_000
            while (app.session.clientBridge == null && app.session.state !is SessionController.State.Failed && SystemClock.elapsedRealtime() < deadline)
                Thread.sleep(50)
            val bridge = app.session.clientBridge
            assertNotNull("Session did not create its private bridge", bridge)
            var available = false
            while (!available && SystemClock.elapsedRealtime() < deadline) {
                assertFalse("Steam startup failed", app.session.state is SessionController.State.Failed)
                available = try { bridge!!.hasClientInterface() } catch (_: IllegalStateException) { false }
                if (!available) Thread.sleep(100)
            }
            assertTrue("Normal session must expose the actual Linux client interface", available)
            var online = false
            while (!online && SystemClock.elapsedRealtime() < deadline) {
                assertFalse("Steam ended before authentication could be checked", app.session.state is SessionController.State.Failed || app.session.state == SessionController.State.Idle)
                online = try { bridge!!.hasOnlineUser() } catch (_: IllegalStateException) { false }
                if (!online) Thread.sleep(250)
            }
            assertTrue("Private current-user observer must recognize the cached online session", online)
            instrumentation.runOnMainSync { app.session.stop() }
            val stopDeadline = SystemClock.elapsedRealtime() + 20_000
            while (app.session.state != SessionController.State.Idle && SystemClock.elapsedRealtime() < stopDeadline) Thread.sleep(50)
            assertEquals(SessionController.State.Idle, app.session.state)
            assertNull(app.session.clientBridge)
            assertFalse(File(context.cacheDir, "session").exists())
            try { bridge!!.hasClientInterface(); fail("Closed session bridge must reject requests") }
            catch (_: IllegalStateException) { }
        } finally {
            instrumentation.runOnMainSync { app.session.stop(); activity.finish() }
        }
    }

    @Test fun privatePipeExposesRuntimeClientInterface() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyAuthTransport") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val app = context.applicationContext as SteamApplication
        assertEquals("Stop Steam before the transport proof", SessionController.State.Idle, app.session.state)
        app.preparation.install { }
        assertTrue(app.preparation.installed)
        val directory = File(context.cacheDir, "auth-transport-test")
        assertFalse(directory.exists())
        assertTrue(directory.mkdirs())
        val command = File(directory, "ui-command")
        val response = File(directory, "ui-response")
        val bridge = SteamClientBridge(directory)
        val activity = instrumentation.startActivitySync(Intent(context, DisplayTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as DisplayTestActivity
        val audio = SessionAudio(context, directory)
        var process: Process? = null
        var reader: Thread? = null
        val diagnostics = java.util.concurrent.ConcurrentHashMap<String, Int>()
        try {
            assertTrue(activity.ready.await(5, TimeUnit.SECONDS))
            audio.start()
            NativeDisplay.startVulkan(File(directory, "wayland-0").path, activity.surface.holder.surface, 60_000,
                File(GraphicsInstaller(context).root, "android").path, context.applicationInfo.nativeLibraryDir)
            val runtime = SessionRuntime(context, directory)
            process = runtime.start(runtime.steamCommand(), 1280, 720)
            // Drain subprocess output without persisting or displaying it.
            val running = process!!
            reader = Thread { try { running.inputStream.bufferedReader().useLines { lines -> lines.forEach { line ->
                for (term in listOf("steamwebhelper", "not found", "error while loading", "Failed", "fatal", "Permission denied", "No such file", "checksum", "verification", "SDL_Init", "mismatch"))
                    if (line.contains(term, ignoreCase = true)) diagnostics.merge(term, 1, Int::plus)
            } } } catch (_: Exception) { } }.apply { start() }
            val deadline = SystemClock.elapsedRealtime() + 90_000
            var found = false
            while (!found && SystemClock.elapsedRealtime() < deadline) {
                found = bridge.hasClientInterface()
                if (!found) Thread.sleep(500)
            }
            assertTrue("Runtime client methods were unavailable on the protected pipe", found)
            assertEquals(0x180, Os.stat(command.path).st_mode and 0x1ff)
            assertEquals(0x180, Os.stat(response.path).st_mode and 0x1ff)
        } finally {
            process?.destroy()
            if (process?.waitFor(3, TimeUnit.SECONDS) == false) { process?.destroyForcibly(); process?.waitFor(3, TimeUnit.SECONDS) }
            reader?.join(3_000)
            NativeDisplay.stop()
            audio.close()
            bridge.close()
            instrumentation.runOnMainSync { activity.finish() }
            RuntimeArchive.delete(directory)
        }
    }
}
