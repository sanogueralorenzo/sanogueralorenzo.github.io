package com.sanogueralorenzo.androidsteam

import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.display.DisplayTestActivity
import com.sanogueralorenzo.androidsteam.display.NativeDisplay
import com.sanogueralorenzo.androidsteam.input.SteamSurface
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import com.sanogueralorenzo.androidsteam.session.SessionComponents
import java.io.File
import java.util.Collections
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class InputIntegrationTest {
    @Test fun linuxReceivesTouchTypingModifiersAndFocusReleases() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyInput") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val components = SessionComponents(context)
        assertTrue(components.installed)
        repeat(2) {
            val activity = instrumentation.startActivitySync(Intent(context, DisplayTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as DisplayTestActivity
            val directory = File(context.cacheDir, "input-test").apply { mkdirs() }
            val lines = Collections.synchronizedList(mutableListOf<String>())
            var process: Process? = null
            var reader: Thread? = null
            fun await(line: String) {
                val deadline = SystemClock.elapsedRealtime() + 5_000
                while (!lines.contains(line) && SystemClock.elapsedRealtime() < deadline) Thread.sleep(10)
                assertTrue("Missing $line; received ${synchronized(lines) { lines.toList() }}", lines.contains(line))
            }
            try {
                assertTrue(activity.ready.await(5, TimeUnit.SECONDS))
                NativeDisplay.start(File(directory, "wayland-0").path, activity.surface.holder.surface, 60_000)
                process = LinuxRuntime(context, RuntimeInstaller(context).root).start(
                    listOf("/opt/androidsteam/app/libwayland-probe.so", "input"),
                    listOf("${context.applicationInfo.nativeLibraryDir}:/opt/androidsteam/app", "${directory.path}:/run/androidsteam", "${components.root.path}:/opt/androidsteam/session"),
                    mapOf("XDG_RUNTIME_DIR" to "/run/androidsteam", "WAYLAND_DISPLAY" to "wayland-0", "LD_LIBRARY_PATH" to "/opt/androidsteam/session/usr/lib/aarch64-linux-gnu"))
                val running = process
                reader = Thread { try { running.inputStream.bufferedReader().useLines { it.forEach(lines::add) } } catch (_: java.io.IOException) { } }.apply { start() }
                await("input-ready"); await("input-keymap-ok"); await("input-keyboard-focus")
                NativeDisplay.key(42, true); NativeDisplay.key(30, true); NativeDisplay.key(30, false); NativeDisplay.key(42, false)
                await("input-key 30 1 65"); await("input-modifiers 0 0")
                NativeDisplay.pointer(.25f, .75f, 272, true); NativeDisplay.pointer(.25f, .75f, 272, false)
                await("input-pointer 80 150"); await("input-button 272 0")
                instrumentation.runOnMainSync {
                    val surface = activity.surface as SteamSurface
                    val now = SystemClock.uptimeMillis()
                    for ((action, x, y) in listOf(Triple(MotionEvent.ACTION_DOWN, .4f, .2f), Triple(MotionEvent.ACTION_MOVE, .6f, .4f), Triple(MotionEvent.ACTION_UP, .6f, .4f))) {
                        MotionEvent.obtain(now, now, action, surface.width * x, surface.height * y, 0).also { surface.dispatchTouchEvent(it); it.recycle() }
                    }
                }
                for (code in listOf(KeyEvent.KEYCODE_B, KeyEvent.KEYCODE_R, KeyEvent.KEYCODE_SHIFT_LEFT, KeyEvent.KEYCODE_C))
                    instrumentation.sendKeySync(KeyEvent(KeyEvent.ACTION_DOWN, code))
                for (code in listOf(KeyEvent.KEYCODE_B, KeyEvent.KEYCODE_R, KeyEvent.KEYCODE_C, KeyEvent.KEYCODE_SHIFT_LEFT))
                    instrumentation.sendKeySync(KeyEvent(KeyEvent.ACTION_UP, code))
                instrumentation.sendKeySync(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
                instrumentation.sendKeySync(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
                await("input-key 48 1 98"); await("input-key 19 1 114"); await("input-key 46 1 67"); await("input-key 14 0 8")
                await("input-touch-down 0 128 40"); await("input-touch-motion 0 192 80"); await("input-touch-up 0")
                NativeDisplay.key(32, true); NativeDisplay.pointer(.2f, .2f, 273, true); NativeDisplay.touch(2, 0, .2f, .2f)
                await("input-key 32 1 100"); await("input-button 273 1"); await("input-touch-down 2 64 40")
                NativeDisplay.attach(null)
                await("input-key 32 0 100"); await("input-button 273 0"); await("input-touch-cancel")
                NativeDisplay.attach(activity.surface.holder.surface)
                instrumentation.sendKeySync(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                instrumentation.sendKeySync(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
                await("input-key 28 0 13")
            } finally {
                process?.destroy()
                if (process?.waitFor(3, TimeUnit.SECONDS) == false) { process?.destroyForcibly(); process?.waitFor(3, TimeUnit.SECONDS) }
                reader?.join(3_000)
                NativeDisplay.stop()
                instrumentation.runOnMainSync { activity.finish() }
                directory.deleteRecursively()
            }
        }
    }
}
