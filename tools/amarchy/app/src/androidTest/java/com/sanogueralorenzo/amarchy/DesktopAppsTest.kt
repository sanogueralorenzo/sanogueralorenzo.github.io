package com.sanogueralorenzo.amarchy

import android.content.Intent
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.amarchy.session.DesktopSession
import com.sanogueralorenzo.amarchy.session.Phase
import com.sanogueralorenzo.amarchy.desktop.DesktopSurface
import org.json.JSONArray
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DesktopAppsTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val workspace get() = (context.applicationContext as AmarchyApplication).workspace

    @Test fun bundledFilesEditorAndBrowserOpenAsRealDesktopWindows() {
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val desktop = DesktopSession(context)
        try {
            instrumentation.runOnMainSync { descendants(activity.window.decorView).filterIsInstance<Button>().first { it.text == "Get started" }.performClick() }
            val deadline = SystemClock.elapsedRealtime() + 90_000
            while (workspace.state.phase != Phase.RUNNING && SystemClock.elapsedRealtime() < deadline) {
                if (workspace.state.phase == Phase.FAILED) fail(workspace.state.detail)
                Thread.sleep(50)
            }
            assertEquals(Phase.RUNNING, workspace.state.phase)
            for ((command, expected) in listOf(
                "nautilus --new-window /root/Projects" to "nautilus",
                "foot --app-id=amarchy-editor --title=Neovim nvim" to "amarchy-editor",
                "chromium --ozone-platform=wayland --no-sandbox --disable-gpu --no-first-run --no-default-browser-check" to "chromium")) {
                instrumentation.runOnMainSync { workspace.launch("$command > /run/user/1000/app-$expected.log 2>&1") }
                val opened = SystemClock.elapsedRealtime() + 45_000
                var windows = ""
                var found = false
                do {
                    windows = desktop.command(listOf("/usr/bin/hyprctl", "-j", "clients"))
                    val clients = JSONArray(windows)
                    found = (0 until clients.length()).any {
                        val client = clients.getJSONObject(it)
                        val identity = client.optString("class") + " " + client.optString("title")
                        client.optBoolean("mapped") && identity.contains(expected, ignoreCase = true)
                    }
                    if (found) break
                    Thread.sleep(100)
                } while (SystemClock.elapsedRealtime() < opened)
                val diagnostic = File(context.cacheDir, "s/app-$expected.log").takeIf { it.exists() }?.readText().orEmpty().takeLast(5000)
                assertTrue("$expected did not open: $diagnostic\n$windows", found)
                println("desktop app mapped: $expected")
                Thread.sleep(1000)
                var surface: DesktopSurface? = null
                instrumentation.runOnMainSync { surface = descendants(activity.window.decorView).filterIsInstance<DesktopSurface>().single() }
                val image = Bitmap.createBitmap(1280, 720, Bitmap.Config.ARGB_8888)
                val copied = CountDownLatch(1)
                var result = -1
                PixelCopy.request(surface!!, image, { result = it; copied.countDown() }, Handler(Looper.getMainLooper()))
                assertTrue(copied.await(5, TimeUnit.SECONDS)); assertEquals(PixelCopy.SUCCESS, result)
                File(context.cacheDir, "app-$expected.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
                image.recycle()
            }
        } finally {
            instrumentation.runOnMainSync { workspace.stop() }
            val stopped = SystemClock.elapsedRealtime() + 15_000
            while (workspace.state.phase == Phase.STOPPING && SystemClock.elapsedRealtime() < stopped) Thread.sleep(50)
            assertEquals(Phase.WELCOME, workspace.state.phase)
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
}
