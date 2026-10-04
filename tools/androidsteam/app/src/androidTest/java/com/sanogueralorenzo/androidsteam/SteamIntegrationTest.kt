package com.sanogueralorenzo.androidsteam

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import com.sanogueralorenzo.androidsteam.session.SteamInstaller
import com.sanogueralorenzo.androidsteam.session.SessionRuntime
import com.sanogueralorenzo.androidsteam.session.SessionComponents
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SteamIntegrationTest {
    @Test fun browserPeersRequireLiveSocketsAndKeepTheListener() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifySteam") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val components = SessionComponents(context)
        assertTrue(components.installed)
        val directory = File(context.cacheDir, "steam-peer-test").apply { deleteRecursively(); mkdirs() }
        File(directory, "ports").mkdir()
        val process = LinuxRuntime(context, RuntimeInstaller(context).root).start(
            listOf("/opt/androidsteam/app/libsocket-peer-probe.so"),
            listOf("${context.applicationInfo.nativeLibraryDir}:/opt/androidsteam/app", "${components.root.path}:/opt/androidsteam/session",
                "${components.root.path}/usr/bin/steam-socket-peer:/usr/bin/lsof", "${directory.path}:/run/androidsteam"),
            mapOf("LD_PRELOAD" to "/opt/androidsteam/session/usr/lib/aarch64-linux-gnu/libdeck-ports.so"))
        try {
            assertTrue("Socket peer check timed out", process.waitFor(15, TimeUnit.SECONDS))
            val output = process.inputStream.bufferedReader().readText()
            assertEquals(output, 0, process.exitValue())
            assertTrue(output, output.contains("Live socket peers verified"))
        } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS); directory.deleteRecursively() }
    }

    @Test fun steamMutexListMatchesGlibcInThreadsAndForks() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifySteam") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val components = SessionComponents(context)
        assertTrue(components.installed)
        val process = LinuxRuntime(context, RuntimeInstaller(context).root).start(
            listOf("/opt/androidsteam/app/librobust-probe.so"),
            listOf("${context.applicationInfo.nativeLibraryDir}:/opt/androidsteam/app", "${components.root.path}:/opt/androidsteam/session"),
            mapOf("LD_PRELOAD" to "/opt/androidsteam/session/usr/lib/aarch64-linux-gnu/libdeck-robust.so"))
        try {
            assertTrue("Thread mutex-list check timed out", process.waitFor(15, TimeUnit.SECONDS))
            val output = process.inputStream.bufferedReader().readText()
            assertEquals(output, 0, process.exitValue())
            assertTrue(output, output.contains("Robust lists verified"))
        } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS) }
    }

    @Test fun bootstrapRestartIsBoundedAndReturnsClientStatus() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifySteam") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "steam-launch-test").apply { mkdirs() }
        val runtime = RuntimeInstaller(context)
        assertTrue(runtime.installed)
        try {
            context.assets.open("steam/launch.sh").use { input -> File(directory, "launch.sh").outputStream().use { input.copyTo(it) } }
            for ((client, exit, calls) in listOf(Triple("[ \"\$n\" -lt 2 ] && exit 42; exit 0", 0, 2), Triple("exit 42", 42, 3), Triple("exit 7", 7, 1), Triple("kill -TERM \$\$", 143, 1))) {
                File(directory, "count").writeText("0")
                File(directory, "client.sh").writeText("n=\$(cat /opt/androidsteam/test/count); n=\$((n + 1)); echo \$n > /opt/androidsteam/test/count; $client\n")
                val process = LinuxRuntime(context, runtime.root).start(
                    listOf("/bin/sh", "/opt/androidsteam/test/launch.sh", "/bin/sh", "/opt/androidsteam/test/client.sh"),
                    listOf("${directory.path}:/opt/androidsteam/test", "${directory.path}:/run/androidsteam"))
                try {
                    assertTrue("Bootstrap restart did not finish", process.waitFor(10, TimeUnit.SECONDS))
                    val output = process.inputStream.bufferedReader().readText()
                    assertEquals(output, exit, process.exitValue())
                    assertEquals(exit, File(directory, "steam-exit").readText().trim().toInt())
                    assertEquals(calls, File(directory, "count").readText().trim().toInt())
                } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS) }
            }
        } finally { directory.deleteRecursively() }
    }

    @Test fun browserDependenciesFontsAndLinuxDnsAreAvailable() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifySteam") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "steam-network-test").apply { mkdirs() }
        val components = SessionComponents(context)
        assertTrue(SteamInstaller(context).installed && components.installed)
        try {
            SessionRuntime(context, directory).steamCommand()
            val process = LinuxRuntime(context, RuntimeInstaller(context).root).start(
                listOf("/bin/sh", "-c", "set -e; ldd /root/.steam/binarm64/steamwebhelper; ldd /root/.steam/binarm64/steamui.so; ldd /root/.steam/binarm64/steamclient.so; getent ahosts client-update.akamai.steamstatic.com; /opt/androidsteam/session/usr/bin/fc-list"),
                listOf("${components.root.path}:/opt/androidsteam/session", "${components.root.path}/usr/share/fonts:/usr/share/fonts",
                    "${components.root.path}/usr/share/fontconfig:/usr/share/fontconfig", "${components.root.path}/etc/fonts:/etc/fonts"),
                mapOf("LD_LIBRARY_PATH" to "/root/.steam/binarm64:/opt/androidsteam/session/usr/lib/aarch64-linux-gnu:/opt/androidsteam/session/usr/lib/aarch64-linux-gnu/pulseaudio"))
            try {
                assertTrue("Steam dependency/network check timed out", process.waitFor(20, TimeUnit.SECONDS))
                val output = process.inputStream.bufferedReader().readText()
                assertEquals(output, 0, process.exitValue())
                assertFalse(output, output.contains("not found"))
                assertTrue(output, output.contains("STREAM") && output.contains("DejaVu Sans"))
            } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS) }
        } finally { directory.deleteRecursively() }
    }

    @Test fun stableArm64ClientInstallsWithoutLosingUserData() {
        assumeTrue("Opt in to Valve's 358 MB Steam client download", InstrumentationRegistry.getArguments().getString("verifySteam") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val runtime = RuntimeInstaller(context)
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
