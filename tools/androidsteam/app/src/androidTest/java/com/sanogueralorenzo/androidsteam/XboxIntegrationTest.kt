package com.sanogueralorenzo.androidsteam

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.input.PadBridge
import com.sanogueralorenzo.androidsteam.input.PadState
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import com.sanogueralorenzo.androidsteam.session.SessionComponents
import java.io.File
import java.util.Collections
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import android.content.Intent
import android.os.SystemClock
import android.view.MotionEvent
import com.sanogueralorenzo.androidsteam.display.DisplayTestActivity
import com.sanogueralorenzo.androidsteam.display.NativeDisplay
import com.sanogueralorenzo.androidsteam.input.ControlProfile
import com.sanogueralorenzo.androidsteam.input.OnScreenControls

@RunWith(AndroidJUnit4::class)
class XboxIntegrationTest {
    @Test fun renderedXboxAndDirectTouchReachLinuxTogether() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyInput") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val activity = instrumentation.startActivitySync(Intent(context, DisplayTestActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)) as DisplayTestActivity
        val directory = File(context.cacheDir, "xbox-touch-validation").apply { assertTrue(mkdir()) }
        val pad = PadBridge()
        val processes = mutableListOf<Process>()
        val readers = mutableListOf<Thread>()
        val lines = Collections.synchronizedList(mutableListOf<String>())
        fun await(marker: String) {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            while (!lines.contains(marker) && System.nanoTime() < deadline) Thread.sleep(10)
            assertTrue("Missing $marker", lines.contains(marker))
        }
        val down = SystemClock.uptimeMillis()
        fun touch(action: Int, points: List<Pair<Float, Float>>) {
            val properties = points.indices.map { MotionEvent.PointerProperties().apply { id = it; toolType = MotionEvent.TOOL_TYPE_FINGER } }.toTypedArray()
            val coordinates = points.map { point -> MotionEvent.PointerCoords().apply { x = point.first; y = point.second; pressure = 1f; size = 1f } }.toTypedArray()
            val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, points.size, properties, coordinates,
                0, 0, 1f, 1f, 0, 0, android.view.InputDevice.SOURCE_TOUCHSCREEN, 0)
            instrumentation.runOnMainSync { activity.overlay.dispatchTouchEvent(event) }; event.recycle()
        }
        try {
            assertTrue(activity.ready.await(5, TimeUnit.SECONDS))
            pad.start(directory)
            NativeDisplay.start(File(directory, "wayland-0").path, activity.surface.holder.surface, 60_000)
            val components = SessionComponents(context)
            val runtime = LinuxRuntime(context, RuntimeInstaller(context).root)
            fun probe(name: String, arguments: List<String> = emptyList()): Process {
                val process = runtime.start(listOf("/opt/androidsteam/app/$name") + arguments,
                    listOf("${context.applicationInfo.nativeLibraryDir}:/opt/androidsteam/app", "${components.root.path}:/opt/androidsteam/session",
                        "${directory.path}:/run/androidsteam", "${directory.path}/input:/dev/input", "${directory.path}/uinput:/dev/uinput"),
                    mapOf("XDG_RUNTIME_DIR" to "/run/androidsteam", "WAYLAND_DISPLAY" to "wayland-0",
                        "LD_LIBRARY_PATH" to "/opt/androidsteam/session/usr/lib", "LD_PRELOAD" to "/opt/androidsteam/session/usr/lib/libxbox-evdev.so",
                        "FAKE_EVDEV_DIR" to "/run/androidsteam/input", "FAKE_EVDEV_MEMFD_PATHS" to "0=/run/androidsteam/input-rings/ring0", "FAKE_EVDEV_UINPUT" to "1"))
                processes += process
                readers += Thread { try { process.inputStream.bufferedReader().useLines { it.forEach(lines::add) } } catch (_: java.io.IOException) { } }.apply { start() }
                return process
            }
            probe("libwayland-probe.so", listOf("input")); await("input-ready"); await("input-keyboard-focus")
            instrumentation.runOnMainSync { activity.overlay.configure(ControlProfile.XBOX, pad) }
            val xbox = activity.findViewById<OnScreenControls>(R.id.xbox_controls)
            val layoutDeadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
            var laidOut = false
            while (!laidOut && System.nanoTime() < layoutDeadline) {
                instrumentation.runOnMainSync { laidOut = xbox.width > 0 && !xbox.isLayoutRequested }
                if (!laidOut) Thread.sleep(20)
            }
            assertTrue("Xbox controls did not lay out", laidOut)
            val cells = OnScreenControls::class.java.getDeclaredField("controls").apply { isAccessible = true }.get(xbox) as List<*>
            fun value(id: String, field: String): Float {
                val cell = cells.first { it!!.javaClass.getDeclaredField("id").apply { isAccessible = true }.get(it) == id }!!
                return cell.javaClass.getDeclaredField(field).apply { isAccessible = true }.getFloat(cell)
            }
            fun point(id: String) = value(id, "cx") to value(id, "cy")
            val held = listOf(point("a"), point("guide"), point("ls"))
            touch(MotionEvent.ACTION_DOWN, held.take(1))
            touch(MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), held.take(2))
            touch(MotionEvent.ACTION_POINTER_DOWN or (2 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), held)
            val moved = held.take(2) + listOf((held[2].first + value("ls", "radius") * .5f) to held[2].second)
            touch(MotionEvent.ACTION_MOVE, moved)
            val controller = probe("libxbox-probe.so"); await("xbox-recognized-held")
            val together = moved + listOf(activity.overlay.width * .5f to activity.overlay.height * .5f)
            touch(MotionEvent.ACTION_POINTER_DOWN or (3 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), together)
            await("input-touch-down 3 160 100")
            assertTrue("Direct touch ended the held controller input", controller.isAlive)
            touch(MotionEvent.ACTION_POINTER_UP or (3 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), together)
            for (index in 2 downTo 1) touch(MotionEvent.ACTION_POINTER_UP or (index shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), moved.take(index + 1))
            touch(MotionEvent.ACTION_UP, moved.take(1))
            await("input-touch-up 3"); await("xbox-released"); await("steam-input-uinput-recognized")
            assertTrue(controller.waitFor(5, TimeUnit.SECONDS)); assertEquals(0, controller.exitValue())
        } finally {
            processes.forEach { it.destroyForcibly(); it.waitFor(3, TimeUnit.SECONDS) }
            readers.forEach { it.join(1_000) }
            pad.close(); NativeDisplay.stop()
            instrumentation.runOnMainSync { activity.finish() }
            RuntimeArchive.delete(directory)
        }
    }

    @Test fun linuxRecognizesXboxSnapshotReleaseAndSteamInputVirtualDevice() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyInput") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "xbox-validation").apply { assertTrue(mkdir()) }
        val pad = PadBridge()
        val components = SessionComponents(context)
        var process: Process? = null
        var reader: Thread? = null
        val lines = Collections.synchronizedList(mutableListOf<String>())
        try {
            components.install { }
            pad.start(directory)
            pad.applyTouch { it.press(PadState.A, true); it.press(PadState.GUIDE, true); it.leftX = .5f }
            val runtime = LinuxRuntime(context, RuntimeInstaller(context).root)
            val bindings = listOf("${context.applicationInfo.nativeLibraryDir}:/opt/androidsteam/app", "${components.root.path}:/opt/androidsteam/session",
                "${directory.path}:/run/androidsteam", "${directory.path}/input:/dev/input", "${directory.path}/uinput:/dev/uinput")
            val environment = mapOf("LD_PRELOAD" to "/opt/androidsteam/session/usr/lib/libxbox-evdev.so", "FAKE_EVDEV_DIR" to "/run/androidsteam/input",
                "FAKE_EVDEV_MEMFD_PATHS" to "0=/run/androidsteam/input-rings/ring0", "FAKE_EVDEV_UINPUT" to "1")
            val running = runtime.start(listOf("/opt/androidsteam/app/libxbox-probe.so"), bindings, environment)
            process = running
            reader = Thread { running.inputStream.bufferedReader().useLines { it.forEach(lines::add) } }.apply { start() }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            while (!lines.contains("xbox-recognized-held") && running.isAlive && System.nanoTime() < deadline) Thread.sleep(20)
            assertTrue(lines.toString(), lines.contains("xbox-recognized-held"))
            pad.releaseTouch()
            assertTrue("Xbox probe timed out", running.waitFor(10, TimeUnit.SECONDS))
            reader.join(1_000)
            assertEquals(lines.toString(), 0, running.exitValue())
            assertTrue(lines.toString(), lines.contains("xbox-released"))
            assertTrue(lines.toString(), lines.contains("steam-input-uinput-recognized"))
            println(lines.joinToString("\n"))
            for ((probe, marker) in listOf("libudev-probe.so" to "udev-other-callers-pass-through",
                "libwinebus.so" to "wine-controller-discovery-and-hot-removal")) {
                val checking = runtime.start(listOf("/opt/androidsteam/app/$probe"), bindings,
                    environment + ("LD_PRELOAD" to "/opt/androidsteam/session/usr/lib/libxbox-udev.so"))
                process = checking
                assertTrue("Wine device probe timed out", checking.waitFor(10, TimeUnit.SECONDS))
                val output = checking.inputStream.bufferedReader().readText()
                assertEquals(output, 0, checking.exitValue())
                assertTrue(output, output.contains(marker))
                println(marker)
            }
        } finally {
            process?.destroyForcibly(); process?.waitFor(3, TimeUnit.SECONDS); reader?.join(1_000)
            pad.close(); RuntimeArchive.delete(directory)
        }
    }
}
