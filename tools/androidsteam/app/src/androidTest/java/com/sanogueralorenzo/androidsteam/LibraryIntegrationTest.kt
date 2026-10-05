package com.sanogueralorenzo.androidsteam

import android.content.Intent
import android.os.SystemClock
import android.widget.EditText
import android.widget.ListView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.games.GameProfiles
import com.sanogueralorenzo.androidsteam.library.SteamLibrary
import com.sanogueralorenzo.androidsteam.session.SessionActivity
import com.sanogueralorenzo.androidsteam.session.SessionController
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LibraryIntegrationTest {
    @Test fun editedProfileRestartsIdleClientBeforeNativePlay() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyProfileRestart") == "true")
        val appId = requireNotNull(InstrumentationRegistry.getArguments().getString("profileAppId")?.toIntOrNull())
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val app = context.applicationContext as SteamApplication
        val profiles = GameProfiles(context)
        val original = profiles.load(appId)
        val steam = instrumentation.startActivitySync(Intent(context, SessionActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        var play: android.app.Activity? = null
        fun waitUntil(timeout: Long, condition: () -> Boolean) {
            val deadline = SystemClock.elapsedRealtime() + timeout
            while (!condition() && SystemClock.elapsedRealtime() < deadline) {
                if (app.session.state is SessionController.State.Failed) fail("Steam session failed")
                Thread.sleep(100)
            }
            assertTrue("Timed out waiting for Steam", condition())
        }
        fun steamPids(): Set<Int> {
            val descriptor = instrumentation.uiAutomation.executeShellCommand("ps -A -o UID,PID,NAME")
            return android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).bufferedReader().useLines { lines ->
                lines.map { it.trim().split(Regex("\\s+")) }.filter {
                    it.size == 3 && it[0] == android.os.Process.myUid().toString() && it[2] == "steam"
                }.map { it[1].toInt() }.toSet()
            }
        }
        try {
            waitUntil(120_000) { app.session.state == SessionController.State.Running && runCatching { SteamLibrary(context).refresh() }.isSuccess }
            assertTrue(SteamLibrary(context).read().games.any { it.appId == appId && it.installed })
            val old = steamPids()
            assertTrue(old.isNotEmpty())
            instrumentation.runOnMainSync { steam.finish() }
            val marker = "native-restart-check"
            profiles.save(appId, original.copy(environment = original.environment + ("ANDROID_STEAM_RESTART_TEST" to marker)))
            assertTrue(app.session.needsRestart)
            // A request can arrive before the replacement activity gets its surface.
            instrumentation.runOnMainSync { app.session.requestGame(appId, false) }
            Thread.sleep(2_000)
            assertNull("The old client must not launch with stale settings", app.session.gameAppId)
            assertEquals(old, steamPids())
            val log = java.io.File(context.filesDir, "home/.local/share/Steam/logs/gameprocess_log.txt")
            val offset = log.length()
            play = instrumentation.startActivitySync(Intent(context, SessionActivity::class.java)
                .putExtra("appId", appId).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            waitUntil(180_000) { app.session.gameAppId == appId }
            assertTrue(steamPids().intersect(old).isEmpty())
            assertFalse(app.session.needsRestart)
            java.io.RandomAccessFile(log, "r").use { file ->
                file.seek(offset.coerceAtMost(file.length()))
                val size = (file.length() - file.filePointer).coerceAtMost(262_144).toInt()
                val bytes = ByteArray(size); file.readFully(bytes)
                assertTrue("Steam's new launch command lacks the saved environment", bytes.toString(Charsets.UTF_8).contains(marker))
            }
        } finally {
            instrumentation.runOnMainSync { app.session.stop(); play?.finish(); steam.finish() }
            try { waitUntil(15_000) { app.session.state == SessionController.State.Idle || app.session.state is SessionController.State.Failed } }
            finally {
                profiles.save(appId, original)
                if (app.session.state == SessionController.State.Idle || app.session.state is SessionController.State.Failed) profiles.apply()
            }
        }
    }

    @Test fun liveLicensesAndInstalledFilesDriveNativeAndOfflineLibrary() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyLibrary") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val app = context.applicationContext as SteamApplication
        val steam = instrumentation.startActivitySync(Intent(context, SessionActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        var native: android.app.Activity? = null
        try {
            val deadline = SystemClock.elapsedRealtime() + 120_000
            var snapshot: com.sanogueralorenzo.androidsteam.library.LibrarySnapshot? = null
            while (snapshot == null && SystemClock.elapsedRealtime() < deadline) {
                if (app.session.state is SessionController.State.Failed) fail("Steam startup failed")
                if (app.session.state == SessionController.State.Running) snapshot = runCatching { SteamLibrary(context).refresh() }.getOrNull()
                if (snapshot == null) Thread.sleep(500)
            }
            val actual = requireNotNull(snapshot) { "Steam did not supply a live license snapshot. Check login in Steam." }
            assertTrue(actual.games.isNotEmpty())
            assertTrue(actual.games.any { it.installed })
            assertTrue(actual.games.all { it.appId > 0 && it.name.isNotBlank() })
            assertEquals(actual.games.map { it.appId }, SteamLibrary(context).read().games.map { it.appId })
            instrumentation.runOnMainSync { steam.finish() }
            native = instrumentation.startActivitySync(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            val activity = native
            Thread.sleep(1_000)
            instrumentation.runOnMainSync {
                val list = activity.findViewById<ListView>(R.id.library_games)
                assertEquals(actual.games.size, list.count)
                activity.findViewById<android.view.View>(R.id.tab_search).performClick()
                activity.findViewById<EditText>(R.id.library_search).setText(actual.games.first().name)
                assertTrue(list.count in 1..actual.games.size)
            }
            instrumentation.runOnMainSync { app.session.stop() }
            val stopDeadline = SystemClock.elapsedRealtime() + 15_000
            while (app.session.state != SessionController.State.Idle && SystemClock.elapsedRealtime() < stopDeadline) Thread.sleep(50)
            assertEquals(SessionController.State.Idle, app.session.state)
            assertEquals(actual.games.map { it.appId }, SteamLibrary(context).read().games.map { it.appId })
            println("Native library: ${actual.games.size} licensed games, ${actual.games.count { it.installed }} installed; offline cache retained.")
        } finally {
            instrumentation.runOnMainSync { app.session.stop(); native?.finish(); steam.finish() }
        }
    }
}
