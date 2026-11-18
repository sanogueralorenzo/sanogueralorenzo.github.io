package com.sanogueralorenzo.androidsteam

import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.InputDevice
import android.view.ViewGroup
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.display.DisplayTestActivity
import com.sanogueralorenzo.androidsteam.display.NativeDisplay
import com.sanogueralorenzo.androidsteam.input.SteamSurface
import com.sanogueralorenzo.androidsteam.input.TouchControls
import com.sanogueralorenzo.androidsteam.input.ControlProfile
import com.sanogueralorenzo.androidsteam.input.TouchKey
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
            val activity = instrumentation.startActivitySync(Intent(context, DisplayTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as DisplayTestActivity
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
                val focusDeadline = SystemClock.elapsedRealtime() + 5_000
                while (!activity.hasWindowFocus() && SystemClock.elapsedRealtime() < focusDeadline) Thread.sleep(20)
                assertTrue("Close system panels before checking Android input", activity.hasWindowFocus())
                NativeDisplay.start(File(directory, "wayland-0").path, activity.surface.holder.surface, 60_000)
                process = LinuxRuntime(context, RuntimeInstaller(context).root).start(
                    listOf("/opt/androidsteam/app/libwayland-probe.so", "input"),
                    listOf("${context.applicationInfo.nativeLibraryDir}:/opt/androidsteam/app", "${directory.path}:/run/androidsteam", "${components.root.path}:/opt/androidsteam/session"),
                    mapOf("XDG_RUNTIME_DIR" to "/run/androidsteam", "WAYLAND_DISPLAY" to "wayland-0", "LD_LIBRARY_PATH" to "/opt/androidsteam/session/usr/lib"))
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
                instrumentation.runOnMainSync {
                    val surface = activity.surface as SteamSurface
                    surface.releaseInput()
                    surface.profile = ControlProfile.ARROWS
                    val controls = TouchControls(context).apply { this.surface = surface }
                    activity.addContentView(controls, ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
                    controls.layout(0, 0, surface.width, surface.height)
                    val density = context.resources.displayMetrics.density
                    val stickX = 100f * density; val stickY = surface.height - 100f * density
                    val enterX = surface.width - 58f * density; val enterY = surface.height - 70f * density
                    fun touch(action: Int, points: List<Pair<Float, Float>>) {
                        val now = SystemClock.uptimeMillis()
                        val properties = Array(points.size) { id -> MotionEvent.PointerProperties().apply { this.id = id; toolType = MotionEvent.TOOL_TYPE_FINGER } }
                        val coordinates = points.map { point -> MotionEvent.PointerCoords().apply { x = point.first; y = point.second; pressure = 1f; size = 1f } }.toTypedArray()
                        MotionEvent.obtain(now, now, action, points.size, properties, coordinates, 0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
                            .also { controls.dispatchTouchEvent(it); it.recycle() }
                    }
                    touch(MotionEvent.ACTION_DOWN, listOf(stickX + 45f * density to stickY))
                    touch(MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), listOf(stickX + 45f * density to stickY, enterX to enterY))
                    touch(MotionEvent.ACTION_MOVE, listOf(stickX - 45f * density to stickY, enterX to enterY))
                    touch(MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), listOf(stickX - 45f * density to stickY, enterX to enterY))
                    // Losing focus releases movement even if the finger never came up.
                    controls.onWindowFocusChanged(false)
                    controls.extraKeys = listOf(TouchKey.P, TouchKey.R, TouchKey.CTRL, TouchKey.SHIFT)
                    val extraY = surface.height - 142f * density
                    // Extra keys use the same coalesced input path, including held modifiers.
                    for (index in 0..3) {
                        val x = surface.width - (58f + index * 68f) * density
                        touch(MotionEvent.ACTION_DOWN, listOf(x to extraY))
                        if (index == 2) controls.onWindowFocusChanged(false)
                        else touch(MotionEvent.ACTION_UP, listOf(x to extraY))
                    }
                    controls.visibility = android.view.View.GONE
                    surface.requestFocus()
                    activity.overlay.configure(ControlProfile.ARROWS, com.sanogueralorenzo.androidsteam.input.PadBridge())
                    val points = listOf(stickX + 45f * density to stickY, surface.width * .5f to surface.height * .5f)
                    fun route(action: Int, positions: List<Pair<Float, Float>>) {
                        val time = SystemClock.uptimeMillis()
                        val properties = Array(positions.size) { id -> MotionEvent.PointerProperties().apply { this.id = id; toolType = MotionEvent.TOOL_TYPE_FINGER } }
                        val coordinates = positions.map { point -> MotionEvent.PointerCoords().apply { x = point.first; y = point.second; pressure = 1f; size = 1f } }.toTypedArray()
                        MotionEvent.obtain(time, time, action, positions.size, properties, coordinates, 0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
                            .also { activity.overlay.dispatchTouchEvent(it); it.recycle() }
                    }
                    // Controls first, then direct touch: the outside pointer reaches Linux while movement remains held.
                    route(MotionEvent.ACTION_DOWN, listOf(points[0]))
                    route(MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), points)
                    route(MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), points)
                    route(MotionEvent.ACTION_UP, listOf(points[0]))
                    // Direct touch first, then controls: the original touch keeps its ownership.
                    route(MotionEvent.ACTION_DOWN, listOf(points[1]))
                    route(MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), points.reversed())
                    route(MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), points.reversed())
                    route(MotionEvent.ACTION_UP, listOf(points[1]))
                    activity.overlay.release()
                    activity.overlay.configure(ControlProfile.TOUCH, com.sanogueralorenzo.androidsteam.input.PadBridge())
                    val originalBounds = android.graphics.Rect(surface.left, surface.top, surface.right, surface.bottom)
                    surface.layout(100, 50, originalBounds.right - 100, originalBounds.bottom - 50)
                    val offsetPoint = (surface.left + surface.width * .3f) to (surface.top + surface.height * .3f)
                    route(MotionEvent.ACTION_DOWN, listOf(offsetPoint))
                    route(MotionEvent.ACTION_UP, listOf(offsetPoint))
                    surface.layout(originalBounds.left, originalBounds.top, originalBounds.right, originalBounds.bottom)
                    val preferences = context.getSharedPreferences("controls", android.content.Context.MODE_PRIVATE)
                    val original = preferences.getString("200", null)
                    ControlProfile.save(context, 200, ControlProfile.WASD)
                    assertEquals(ControlProfile.WASD, ControlProfile.load(context, 200))
                    preferences.edit().putString("200", original).apply()
                    surface.profile = ControlProfile.TOUCH
                }
                await("input-key 106 1 0"); await("input-key 105 1 0"); await("input-key 105 0 0")
                await("input-key 28 1 13"); await("input-key 28 0 13")
                await("input-key 25 1 112"); await("input-key 25 0 112")
                await("input-key 29 1 0"); await("input-key 29 0 0")
                await("input-touch-down 1 160 100"); await("input-touch-up 1")
                await("input-touch-down 0 160 100"); await("input-touch-up 0")
                await("input-touch-down 0 96 60")
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
