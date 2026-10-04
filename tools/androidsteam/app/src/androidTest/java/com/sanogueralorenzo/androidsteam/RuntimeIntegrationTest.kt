package com.sanogueralorenzo.androidsteam

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.runtime.RuntimeController
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RuntimeIntegrationTest {
    @Test fun downloadsVerifiedRuntimeAndRunsLinuxTwice() {
        assumeTrue("Opt in to the 98 MB runtime download", InstrumentationRegistry.getArguments().getString("verifyRuntime") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val controller = (context.applicationContext as SteamApplication).runtime
        if (controller.state == RuntimeController.State.Missing) {
            val preserved = File.createTempFile("validation-", ".txt", File(context.filesDir, "home"))
            try {
                preserved.writeText("keep user data")
                instrumentation.runOnMainSync { controller.install() }
                val archive = File(context.cacheDir, "runtime.tar.xz")
                val deadline = System.nanoTime() + 30_000_000_000
                while (archive.length() == 0L && controller.state is RuntimeController.State.Working && System.nanoTime() < deadline) Thread.sleep(100)
                assertTrue("Download did not start: ${controller.state}", archive.length() > 0L)
                instrumentation.runOnMainSync { controller.stop(); controller.install() }
                awaitReady(controller, 300_000)
                assertEquals("keep user data", preserved.readText())
                assertFalse(File(context.filesDir, "runtime-staging").exists())
                assertFalse(archive.exists())
            } finally { preserved.delete() }
        }
        instrumentation.runOnMainSync { controller.install() }
        awaitReady(controller, 300_000)
        repeat(2) {
            instrumentation.runOnMainSync { controller.check() }
            val result = awaitReady(controller, 20_000)
            assertTrue(result.output, result.output.contains("GLIBC") && result.output.contains("aarch64"))
            println(result.output)
        }
        instrumentation.runOnMainSync { controller.check(); controller.stop() }
        assertTrue(controller.state is RuntimeController.State.Failed)
        instrumentation.runOnMainSync { controller.check() }
        assertTrue(awaitReady(controller, 20_000).output.contains("Linux runtime ready"))
        // The current base stores Coreutils commands as aliases of one executable.
        val process = LinuxRuntime(context, RuntimeInstaller(context).root).start(
            listOf("/usr/bin/dash", "-c", "set -e; /usr/bin/ls -d /usr; /usr/bin/cp --version; /usr/bin/basename /tmp/test; /usr/bin/sha256sum /etc/os-release"))
        try {
            assertTrue("Linux command aliases timed out", process.waitFor(10, TimeUnit.SECONDS))
            val output = process.inputStream.bufferedReader().readText()
            assertEquals(output, 0, process.exitValue())
            assertTrue(output, output.contains("/usr") && output.contains("cp") && output.contains("test") && output.contains("/etc/os-release"))
            println(output)
        } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS) }
    }

    private fun awaitReady(controller: RuntimeController, timeout: Long): RuntimeController.State.Ready {
        val deadline = System.nanoTime() + timeout * 1_000_000
        while (controller.state is RuntimeController.State.Working && System.nanoTime() < deadline) Thread.sleep(100)
        val state = controller.state
        assertTrue("Expected ready state, got $state", state is RuntimeController.State.Ready)
        return state as RuntimeController.State.Ready
    }
}
