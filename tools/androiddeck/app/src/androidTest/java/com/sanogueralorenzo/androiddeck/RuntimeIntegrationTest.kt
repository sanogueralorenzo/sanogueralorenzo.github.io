package com.sanogueralorenzo.androiddeck

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androiddeck.runtime.RuntimeController
import java.io.File
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RuntimeIntegrationTest {
    @Test fun downloadsVerifiedRuntimeAndRunsLinuxTwice() {
        assumeTrue("Opt in to the 78 MB runtime download", InstrumentationRegistry.getArguments().getString("verifyRuntime") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val controller = (context.applicationContext as DeckApplication).runtime
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
    }

    private fun awaitReady(controller: RuntimeController, timeout: Long): RuntimeController.State.Ready {
        val deadline = System.nanoTime() + timeout * 1_000_000
        while (controller.state is RuntimeController.State.Working && System.nanoTime() < deadline) Thread.sleep(100)
        val state = controller.state
        assertTrue("Expected ready state, got $state", state is RuntimeController.State.Ready)
        return state as RuntimeController.State.Ready
    }
}
