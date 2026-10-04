package com.sanogueralorenzo.androiddeck

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androiddeck.runtime.LinuxRuntime
import com.sanogueralorenzo.androiddeck.runtime.RuntimeInstaller
import com.sanogueralorenzo.androiddeck.session.SteamInstaller
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SteamIntegrationTest {
    @Test fun stableArm64ClientInstallsWithoutLosingUserData() {
        assumeTrue("Opt in to Valve's 358 MB Steam client download", InstrumentationRegistry.getArguments().getString("verifySteam") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val runtime = RuntimeInstaller(context.filesDir, context.cacheDir)
        assertTrue("Install the Linux runtime first", runtime.installed)
        val installer = SteamInstaller(context)
        val preserved = File.createTempFile("steam-validation-", ".txt", File(context.filesDir, "home"))
        try {
            preserved.writeText("keep user data")
            if (!installer.installed) {
                Thread.currentThread().interrupt()
                try { assertThrows(CancellationException::class.java) { installer.install {} } }
                finally { Thread.interrupted() }
                assertFalse(File(context.filesDir, "steam-staging").exists())
            }
            installer.install { println(it) }
            assertTrue(installer.installed)
            installer.install { fail("An installed Steam client should not download again") }
            assertEquals("keep user data", preserved.readText())
            assertFalse(File(context.filesDir, "steam-staging").exists())
            assertFalse(File(context.cacheDir, "steam.zip").exists())
            val process = LinuxRuntime(context, runtime.root).start(listOf("/usr/bin/dash", "-c",
                "test -x /root/.steam/binarm64/steam && test -f /root/.steam/sdkarm64/steamclient.so && /usr/bin/ldd /root/.steam/binarm64/steam"))
            try {
                assertTrue("Linux Steam dependency inspection timed out", process.waitFor(20, TimeUnit.SECONDS))
                val output = process.inputStream.bufferedReader().readText()
                assertEquals(output, 0, process.exitValue())
                println("Steam client dependency inspection:\n$output")
            } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS) }
        } finally { preserved.delete() }
    }
}
