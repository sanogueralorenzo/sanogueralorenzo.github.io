package com.sanogueralorenzo.androidsteam

import android.content.Intent
import android.os.SystemClock
import android.view.MotionEvent
import com.sanogueralorenzo.androidsteam.input.ControlProfile
import com.sanogueralorenzo.androidsteam.input.InputOverlay
import com.sanogueralorenzo.androidsteam.input.OnScreenControls
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.session.SessionActivity
import com.sanogueralorenzo.androidsteam.session.SessionController
import com.sanogueralorenzo.androidsteam.session.SessionComponents
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import java.util.Collections
import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in rendered-controls check through the same x64 Windows API games use. */
@RunWith(AndroidJUnit4::class)
class ControllerGameplayIntegrationTest {
    @Test fun renderedXboxReachesWindowsGameApi() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyControllerGame") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val session = (context.applicationContext as SteamApplication).session
        val original = ControlProfile.load(context, 732430)
        try {
            instrumentation.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            ControlProfile.save(context, 732430, ControlProfile.XBOX)
            context.startActivity(Intent(context, SessionActivity::class.java).putExtra("appId", 732430).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            val deadline = System.nanoTime() + TimeUnit.MINUTES.toNanos(5)
            while (session.gameAppId != 732430 && session.state !is SessionController.State.Failed && System.nanoTime() < deadline) Thread.sleep(250)
            assertEquals("Superflight launch; state=${session.state}; action=${session.actionMessage}", 732430, session.gameAppId)
            var resumed: SessionActivity? = null
            instrumentation.runOnMainSync { resumed = androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry.getInstance()
                .getActivitiesInStage(androidx.test.runner.lifecycle.Stage.RESUMED).filterIsInstance<SessionActivity>().single() }
            val activity = requireNotNull(resumed)
            Thread.sleep(15_000)
            val directory = File(context.cacheDir, "session")
            context.assets.open("xinput-probe-x64.exe").use { input -> File(directory, "xinput-probe.exe").outputStream().use(input::copyTo) }
            val proton = "/root/.local/share/Steam/steamapps/common/Proton Experimental (ARM64)"
            val probe = LinuxRuntime(context, RuntimeInstaller(context).root).start(listOf("$proton/files/bin-arm64/wine", "/run/androidsteam/xinput-probe.exe"),
                listOf("${directory.path}:/run/androidsteam", "${directory.path}/input:/dev/input", "${directory.path}/uinput:/dev/uinput",
                    "${directory.path}/shm:/dev/shm", "${SessionComponents(context).root.path}:/opt/androidsteam/session"),
                mapOf("WINEPREFIX" to "/root/.local/share/Steam/steamapps/compatdata/732430/pfx", "WINEDEBUG" to "-all",
                    "DISPLAY" to ":0", "XDG_RUNTIME_DIR" to "/run/androidsteam", "LD_LIBRARY_PATH" to "/opt/androidsteam/session/usr/lib:/usr/lib/pulseaudio",
                    "LD_PRELOAD" to "/opt/androidsteam/session/usr/lib/libxbox-udev.so:/opt/androidsteam/session/usr/lib/libxbox-evdev.so:/opt/androidsteam/session/usr/lib/libsteam-wine-memory.so:/opt/androidsteam/session/usr/lib/libdeck-robust.so",
                    "FAKE_EVDEV_DIR" to "/run/androidsteam/input", "FAKE_EVDEV_MEMFD_PATHS" to "0=/run/androidsteam/input-rings/ring0", "FAKE_EVDEV_UINPUT" to "1"))
            val probeLines = Collections.synchronizedList(mutableListOf<String>())
            val reader = Thread { probe.inputStream.bufferedReader().useLines { it.forEach(probeLines::add) } }.apply { start() }
            try {
                val connected = System.nanoTime() + TimeUnit.SECONDS.toNanos(15)
                while (probe.isAlive && !probeLines.contains("xinput-connected") && System.nanoTime() < connected) Thread.sleep(25)
                assertTrue("x64 XInput did not recognize the pad", probeLines.contains("xinput-connected"))
                val overlay = activity.findViewById<InputOverlay>(R.id.touch_controls)
                val xbox = activity.findViewById<OnScreenControls>(R.id.xbox_controls)
                val cells = OnScreenControls::class.java.getDeclaredField("controls").apply { isAccessible = true }.get(xbox) as List<*>
                fun coordinate(id: String, axis: String): Float {
                    val cell = cells.first { cell -> cell!!.javaClass.getDeclaredField("id").apply { isAccessible = true }.get(cell) == id }!!
                    return cell.javaClass.getDeclaredField(axis).apply { isAccessible = true }.getFloat(cell)
                }
                val aX = coordinate("a", "cx"); val aY = coordinate("a", "cy")
                val lX = coordinate("ls", "cx"); val lY = coordinate("ls", "cy")
                val downTime = SystemClock.uptimeMillis()
                fun touch(action: Int, points: List<Pair<Float, Float>>) {
                    val properties = points.indices.map { MotionEvent.PointerProperties().apply { id = it; toolType = MotionEvent.TOOL_TYPE_FINGER } }.toTypedArray()
                    val coordinates = points.map { point -> MotionEvent.PointerCoords().apply { x = point.first; y = point.second; pressure = 1f; size = 1f } }.toTypedArray()
                    val event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, points.size, properties, coordinates,
                        0, 0, 1f, 1f, 0, 0, android.view.InputDevice.SOURCE_TOUCHSCREEN, 0)
                    instrumentation.runOnMainSync { overlay.dispatchTouchEvent(event) }; event.recycle()
                }
                touch(MotionEvent.ACTION_DOWN, listOf(aX to aY))
                touch(MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), listOf(aX to aY, lX to lY))
                touch(MotionEvent.ACTION_MOVE, listOf(aX to aY, lX + 120f to lY))
                val held = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
                while (probe.isAlive && !probeLines.contains("xinput-A-and-left-stick") && System.nanoTime() < held) Thread.sleep(25)
                touch(MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), listOf(aX to aY, lX + 120f to lY))
                touch(MotionEvent.ACTION_UP, listOf(aX to aY))
                probe.waitFor(5, TimeUnit.SECONDS)
                assertTrue("A and analog stick did not reach x64 XInput", probeLines.contains("xinput-A-and-left-stick"))
                assertTrue("x64 XInput did not release the pad", probeLines.contains("xinput-released"))
                assertFalse("Windows input probe did not exit", probe.isAlive)
                assertEquals(0, probe.exitValue())
            } finally { session.pad.releaseTouch(); probe.destroyForcibly(); reader.join(1_000) }
        } finally {
            ControlProfile.save(context, 732430, original)
            instrumentation.runOnMainSync { session.stop() }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(30)
            while (session.state == SessionController.State.Stopping && System.nanoTime() < deadline) Thread.sleep(50)
            assertNotEquals("Session did not finish cleanup", SessionController.State.Stopping, session.state)
        }
    }
}
