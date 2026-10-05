package com.sanogueralorenzo.androidsteam

import android.content.Intent
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.audio.SessionAudio
import com.sanogueralorenzo.androidsteam.display.DisplayTestActivity
import com.sanogueralorenzo.androidsteam.display.GraphicsInstaller
import com.sanogueralorenzo.androidsteam.display.NativeDisplay
import com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive
import com.sanogueralorenzo.androidsteam.session.SessionController
import com.sanogueralorenzo.androidsteam.session.SessionRuntime
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Capability proof only: no account credentials, token retrieval or authentication changes. */
@RunWith(AndroidJUnit4::class)
class SteamAuthTransportTest {
    @Test fun privatePipeExposesRuntimeAuthenticationMethods() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyAuthTransport") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val app = context.applicationContext as SteamApplication
        assertEquals("Stop Steam before the transport proof", SessionController.State.Idle, app.session.state)
        assertTrue(app.preparation.installed)
        val directory = File(context.cacheDir, "auth-transport-test")
        assertFalse(directory.exists())
        assertTrue(directory.mkdirs())
        val command = File(directory, "ui-command")
        val response = File(directory, "ui-response")
        Os.mkfifo(command.path, 0x180)
        Os.mkfifo(response.path, 0x180)
        val input = Os.open(response.path, OsConstants.O_RDWR or OsConstants.O_NONBLOCK or OsConstants.O_CLOEXEC or OsConstants.O_NOFOLLOW, 0)
        val output = Os.open(command.path, OsConstants.O_RDWR or OsConstants.O_NONBLOCK or OsConstants.O_CLOEXEC or OsConstants.O_NOFOLLOW, 0)
        val activity = instrumentation.startActivitySync(Intent(context, DisplayTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as DisplayTestActivity
        val audio = SessionAudio(context, directory)
        var process: Process? = null
        var reader: Thread? = null
        val diagnostics = java.util.concurrent.ConcurrentHashMap<String, Int>()
        val pending = ByteArrayOutputStream()
        val packets = ArrayDeque<JSONObject>()
        var nextId = 0
        fun request(method: String, parameters: JSONObject = JSONObject(), session: String? = null): JSONObject {
            val id = ++nextId
            val message = JSONObject().put("id", id).put("method", method).put("params", parameters)
            if (session != null) message.put("sessionId", session)
            val bytes = (message.toString() + '\u0000').toByteArray()
            assertEquals("Private command write was incomplete", bytes.size, Os.write(output, bytes, 0, bytes.size))
            val deadline = SystemClock.elapsedRealtime() + 90_000
            val poll = StructPollfd().apply { fd = input; events = OsConstants.POLLIN.toShort() }
            val buffer = ByteArray(4096)
            while (SystemClock.elapsedRealtime() < deadline) {
                while (packets.isNotEmpty()) {
                    val packet = packets.removeFirst()
                    if (packet.optInt("id") == id) {
                        assertFalse("Private Steam UI request failed", packet.has("error"))
                        return packet.getJSONObject("result")
                    }
                }
                assertTrue("Steam ended during the pipe proof", process?.isAlive == true)
                if (Os.poll(arrayOf(poll), 1000) == 0) continue
                val count = Os.read(input, buffer, 0, buffer.size)
                for (i in 0 until count) {
                    if (buffer[i].toInt() == 0) {
                        packets.addLast(JSONObject(pending.toString(Charsets.UTF_8.name())))
                        pending.reset()
                    } else {
                        pending.write(buffer[i].toInt())
                        assertTrue("Private UI response exceeded its limit", pending.size() <= 1_048_576)
                    }
                }
            }
            val phases = File(directory, "ui-probe-status").takeIf { it.isFile }?.readLines().orEmpty()
                .filter { it in listOf("entered", "pipe-failed", "pipe-attached", "exec-failed") }.takeLast(8)
            error("Private Steam UI request timed out; phases=$phases; diagnostics=$diagnostics")
        }
        try {
            assertTrue(activity.ready.await(5, TimeUnit.SECONDS))
            audio.start()
            NativeDisplay.startVulkan(File(directory, "wayland-0").path, activity.surface.holder.surface, 60_000,
                File(GraphicsInstaller(context).root, "android").path, context.applicationInfo.nativeLibraryDir)
            val runtime = SessionRuntime(context, directory)
            val launch = runtime.steamCommand().map {
                if (it.startsWith("LD_PRELOAD=")) it.replace("LD_PRELOAD=", "LD_PRELOAD=/opt/androidsteam/app/libsteam-ui-pipe-probe.so:") else it
            }
            process = runtime.start(launch, 1280, 720)
            // Drain subprocess output without persisting or displaying it.
            val running = process!!
            reader = Thread { try { running.inputStream.bufferedReader().useLines { lines -> lines.forEach { line ->
                for (term in listOf("steamwebhelper", "not found", "error while loading", "Failed", "fatal", "Permission denied", "No such file", "checksum", "verification", "SDL_Init", "mismatch"))
                    if (line.contains(term, ignoreCase = true)) diagnostics.merge(term, 1, Int::plus)
            } } } catch (_: Exception) { } }.apply { start() }
            val deadline = SystemClock.elapsedRealtime() + 90_000
            var found = false
            while (!found && SystemClock.elapsedRealtime() < deadline) {
                val targets = request("Target.getTargets").getJSONArray("targetInfos")
                for (i in 0 until targets.length()) {
                    val target = targets.getJSONObject(i)
                    if (!target.optString("title").contains("SharedJS", ignoreCase = true)) continue
                    val session = request("Target.attachToTarget", JSONObject().put("targetId", target.getString("targetId")).put("flatten", true)).getString("sessionId")
                    val result = request("Runtime.evaluate", JSONObject()
                        .put("expression", "typeof SteamClient !== 'undefined' && typeof SteamClient.Auth.SetLoginToken === 'function' && typeof SteamClient.Auth.StartSignInFromCache === 'function'")
                        .put("returnByValue", true), session)
                    found = result.optJSONObject("result")?.optBoolean("value") == true
                    request("Target.detachFromTarget", JSONObject().put("sessionId", session))
                }
                if (!found) Thread.sleep(500)
            }
            assertTrue("Runtime authentication methods were unavailable on the protected pipe", found)
            assertEquals(0x180, Os.stat(command.path).st_mode and 0x1ff)
            assertEquals(0x180, Os.stat(response.path).st_mode and 0x1ff)
        } finally {
            process?.destroy()
            if (process?.waitFor(3, TimeUnit.SECONDS) == false) { process?.destroyForcibly(); process?.waitFor(3, TimeUnit.SECONDS) }
            reader?.join(3_000)
            NativeDisplay.stop()
            audio.close()
            Os.close(input); Os.close(output)
            instrumentation.runOnMainSync { activity.finish() }
            RuntimeArchive.delete(directory)
        }
    }
}
