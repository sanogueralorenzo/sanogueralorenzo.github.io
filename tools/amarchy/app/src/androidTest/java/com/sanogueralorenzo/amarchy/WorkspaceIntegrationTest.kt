package com.sanogueralorenzo.amarchy

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.amarchy.runtime.EnvironmentInstaller
import com.sanogueralorenzo.amarchy.runtime.LinuxRuntime
import java.io.File
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WorkspaceIntegrationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun cancelledReplacementPreservesThePreviousEnvironment() {
        val directory = File(context.filesDir, "recovery-experiment").apply { mkdirs() }
        val root = File(directory, "environment")
        val previous = File(directory, "environment-previous").apply { mkdirs() }
        File(previous, "preserved").writeText("original")
        try {
            val installer = EnvironmentInstaller(context, root)
            assertEquals("original", File(root, "preserved").readText())
            assertFalse(previous.exists())
            assertThrows(CancellationException::class.java) {
                installer.prepare { detail, progress ->
                    if (detail == "Making room for your desktop" && progress >= 0.1f) throw CancellationException()
                }
            }
            assertEquals("original", File(root, "preserved").readText())
            assertFalse("Cancelled extraction survived", File(directory, "environment-staging").exists())
        } finally { directory.deleteRecursively() }
    }

    @Test fun installsAndRunsArm64LinuxWhilePreservingHome() {
        val installer = EnvironmentInstaller(context)
        installer.prepare { detail, progress -> println("$detail ${(progress * 100).toInt()}%") }
        assertTrue(installer.installed)
        val marker = File(context.filesDir, "home/amarchy-persistence-proof").apply { parentFile!!.mkdirs(); writeText("preserved") }
        try {
            installer.prepare { _, _ -> fail("Installed runtime was prepared twice") }
            val process = LinuxRuntime(context, installer.root, 0).start(listOf("/bin/bash", "-c", "printf 'linux-ok '; uname -m; cat /root/amarchy-persistence-proof; mkdir -p /tmp/amarchy-cli; chmod 700 /tmp/amarchy-cli; XDG_RUNTIME_DIR=/tmp/amarchy-cli Hyprland --version"))
            try {
                assertTrue("Linux command timed out", process.waitFor(30, TimeUnit.SECONDS))
                val output = process.inputStream.bufferedReader().readText()
                println(output)
                assertEquals(output, 0, process.exitValue())
                assertTrue(output, output.contains("linux-ok aarch64"))
                assertTrue(output, output.contains("preserved"))
                assertTrue(output, output.contains("Hyprland"))
            } finally { process.destroyForcibly() }
        } finally { marker.delete() }
    }

}
