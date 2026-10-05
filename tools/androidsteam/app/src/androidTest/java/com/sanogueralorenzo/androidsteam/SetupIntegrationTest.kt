package com.sanogueralorenzo.androidsteam

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.setup.SetupController
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SetupIntegrationTest {
    @Test fun downloadsVerifiedComponentsAndRunsLinuxTwice() {
        assumeTrue("Opt in to complete pinned setup downloads", InstrumentationRegistry.getArguments().getString("verifySetup") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val controller = (context.applicationContext as SteamApplication).setup
        if (controller.state == SetupController.State.Missing) {
            val preserved = File.createTempFile("validation-", ".txt", File(context.filesDir, "home"))
            try {
                preserved.writeText("keep user data")
                instrumentation.runOnMainSync { controller.install() }
                val archive = File(context.cacheDir, "runtime.tar.xz")
                val deadline = System.nanoTime() + 30_000_000_000
                while (archive.length() == 0L && controller.state is SetupController.State.Working && System.nanoTime() < deadline) Thread.sleep(100)
                assertTrue("Download did not start: ${controller.state}", archive.length() > 0L)
                instrumentation.runOnMainSync { controller.stop(); controller.install() }
                awaitReady(controller, 600_000)
                assertEquals("keep user data", preserved.readText())
                assertFalse(File(context.filesDir, "runtime-staging").exists())
                assertFalse(archive.exists())
            } finally { preserved.delete() }
        }
        instrumentation.runOnMainSync { controller.install() }
        awaitReady(controller, 600_000)
        assertTrue((context.applicationContext as SteamApplication).preparation.installed)
        repeat(2) {
            instrumentation.runOnMainSync { controller.check() }
            val result = awaitReady(controller, 20_000)
            assertTrue(result.output, result.output.contains("GNU libc") && result.output.contains("aarch64"))
            println(result.output)
        }
        instrumentation.runOnMainSync { controller.check(); controller.stop() }
        assertTrue(controller.state is SetupController.State.Failed)
        instrumentation.runOnMainSync { controller.check() }
        assertTrue(awaitReady(controller, 20_000).output.contains("Linux runtime ready"))
        // Exercise the real host utilities that Steam’s launch scripts use.
        val process = LinuxRuntime(context, RuntimeInstaller(context).root).start(
            listOf("/usr/bin/dash", "-c", "set -e; /usr/bin/ls -d /usr; /usr/bin/cp --version; /usr/bin/basename /tmp/test; /usr/bin/sha256sum /usr/lib/os-release"))
        try {
            assertTrue("Linux command aliases timed out", process.waitFor(10, TimeUnit.SECONDS))
            val output = process.inputStream.bufferedReader().readText()
            assertEquals(output, 0, process.exitValue())
            assertTrue(output, output.contains("/usr") && output.contains("cp") && output.contains("test") && output.contains("/usr/lib/os-release"))
            println(output)
        } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS) }
    }

    @Test fun sharedPreparationSerializesAndCancelsWaitingCaller() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifySetup") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preparation = (context.applicationContext as SteamApplication).preparation
        assertTrue("Complete setup before testing concurrent preparation", preparation.installed)
        val entered = java.util.concurrent.CountDownLatch(1)
        val release = java.util.concurrent.CountDownLatch(1)
        val failure = java.util.concurrent.atomic.AtomicReference<Throwable?>()
        val waitingFailure = java.util.concurrent.atomic.AtomicReference<Throwable?>()
        val waitingEntered = java.util.concurrent.atomic.AtomicBoolean()
        val first = Thread {
            try { preparation.install { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)) } }
            catch (error: Throwable) { failure.set(error) }
        }
        val second = Thread {
            try { preparation.install { waitingEntered.set(true) } }
            catch (error: Throwable) { waitingFailure.set(error) }
        }
        try {
            first.start()
            assertTrue(entered.await(3, TimeUnit.SECONDS))
            second.start()
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(2)
            while (second.state != Thread.State.WAITING && second.isAlive && System.nanoTime() < deadline) Thread.sleep(10)
            assertEquals("Second preparation must wait for the first", Thread.State.WAITING, second.state)
            assertFalse(waitingEntered.get())
            second.interrupt(); second.join(2_000)
            assertFalse(second.isAlive)
            assertTrue(waitingFailure.get() is InterruptedException)
        } finally {
            release.countDown(); first.join(5_000)
            if (first.isAlive) first.interrupt()
            if (second.isAlive) second.interrupt()
        }
        assertNull(failure.get())
        assertTrue(preparation.installed)
        preparation.install { }
        assertTrue(preparation.installed)
    }

    @Test fun foregroundDownloadCompletesAndStops() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifySetup") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val controller = (context.applicationContext as SteamApplication).setup
        assertTrue("Complete setup before exercising its foreground reuse", (context.applicationContext as SteamApplication).preparation.installed)
        instrumentation.startActivitySync(android.content.Intent(context, MainActivity::class.java)
            .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK or android.content.Intent.FLAG_ACTIVITY_CLEAR_TASK))
        val complete = java.util.concurrent.CountDownLatch(1)
        var working = false
        val observer: (SetupController.State) -> Unit = { state ->
            if (state is SetupController.State.Working) working = true
            if (working && state !is SetupController.State.Working) complete.countDown()
        }
        val service = android.content.Intent(context, com.sanogueralorenzo.androidsteam.setup.SetupService::class.java)
        try {
            instrumentation.runOnMainSync { controller.observe(observer); context.startForegroundService(service) }
            assertTrue("Foreground preparation did not finish", complete.await(10, TimeUnit.SECONDS))
            assertTrue(controller.state is SetupController.State.Ready)
            val manager = context.getSystemService(android.app.ActivityManager::class.java)
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
            @Suppress("DEPRECATION")
            fun running() = manager.getRunningServices(20).any { it.service.className == service.component!!.className }
            while (running() && System.nanoTime() < deadline) Thread.sleep(50)
            assertFalse("Setup foreground service must stop after completion", running())
        } finally {
            instrumentation.runOnMainSync { controller.removeObserver(observer); context.stopService(service) }
        }
    }

    @Test fun freshDownloadCancellationRetryPreservesSeparateHome() {
        assumeTrue("Opt in to isolated complete setup downloads", InstrumentationRegistry.getArguments().getString("verifyFreshSetup") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val original = instrumentation.targetContext
        val directory = File(original.filesDir, "setup-validation")
        assertFalse("Remove only a previous isolated validation directory before retrying", directory.exists())
        val context = object : android.content.ContextWrapper(original) {
            override fun getFilesDir() = File(directory, "files").apply { mkdirs() }
            override fun getCacheDir() = File(directory, "cache").apply { mkdirs() }
        }
        val home = File(context.filesDir, "home").apply { mkdirs() }
        val sentinel = File(home, "keep.txt").apply { writeText("preserve isolated user data") }
        val preparation = com.sanogueralorenzo.androidsteam.setup.SetupInstaller(context)
        val controller = SetupController(context, preparation)
        val archive = File(context.cacheDir, "runtime.tar.xz")
        try {
            assertEquals(SetupController.State.Missing, controller.state)
            instrumentation.runOnMainSync { controller.install() }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(40)
            while (archive.length() == 0L && controller.state is SetupController.State.Working && System.nanoTime() < deadline) Thread.sleep(100)
            assertTrue("Fresh verified download did not start", archive.length() > 0L)
            instrumentation.runOnMainSync { controller.stop(); controller.install() }
            awaitReady(controller, 600_000)
            assertTrue(preparation.installed)
            assertEquals("preserve isolated user data", sentinel.readText())
            assertFalse(archive.exists())
            for (name in listOf("runtime-staging", "graphics-staging", "steam-staging", "session-components-staging"))
                assertFalse("Setup must clean $name", File(context.filesDir, name).exists())
            instrumentation.runOnMainSync { controller.check() }
            assertTrue(awaitReady(controller, 20_000).output.contains("Linux runtime ready"))
            assertTrue("Original setup must remain complete", (original.applicationContext as SteamApplication).preparation.installed)
        } finally {
            instrumentation.runOnMainSync { controller.stop() }
            // Controller work uses a single queue; await a check before removing its files.
            instrumentation.runOnMainSync { controller.check() }
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(20)
            while (controller.state is SetupController.State.Working && System.nanoTime() < deadline) Thread.sleep(100)
            check(controller.state !is SetupController.State.Working) { "Isolated setup is still cleaning up." }
            com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive.delete(directory)
        }
    }

    private fun awaitReady(controller: SetupController, timeout: Long): SetupController.State.Ready {
        val deadline = System.nanoTime() + timeout * 1_000_000
        while (controller.state is SetupController.State.Working && System.nanoTime() < deadline) Thread.sleep(100)
        val state = controller.state
        assertTrue("Expected ready state, got $state", state is SetupController.State.Ready)
        return state as SetupController.State.Ready
    }
}
