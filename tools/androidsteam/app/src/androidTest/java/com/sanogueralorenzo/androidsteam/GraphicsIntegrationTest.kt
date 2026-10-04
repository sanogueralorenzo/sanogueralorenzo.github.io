package com.sanogueralorenzo.androidsteam

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.display.GraphicsInstaller
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GraphicsIntegrationTest {
    @Test fun verifiedPairInstallsAndLinuxDriverResolvesItsDependencies() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyGraphics") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val runtime = RuntimeInstaller(context)
        assertTrue("Install the Linux runtime first", runtime.installed)
        val graphics = GraphicsInstaller(context)
        val preserved = File.createTempFile("graphics-validation-", ".txt", File(context.filesDir, "home"))
        try {
            preserved.writeText("keep user data")
            if (!graphics.installed) {
                Thread.currentThread().interrupt()
                try {
                    assertThrows(CancellationException::class.java) { graphics.install {} }
                } finally { Thread.interrupted() }
                assertFalse(File(context.filesDir, "graphics-staging").exists())
            }
            graphics.install { println(it) }
            assertEquals("keep user data", preserved.readText())
        } finally { preserved.delete() }
        assertTrue(graphics.installed)
        graphics.install { fail("An installed graphics pair should not download again") }
        assertFalse(File(context.filesDir, "graphics-staging").exists())
        assertFalse(File(context.cacheDir, "graphics.zip").exists())
        val linux = LinuxRuntime(context, runtime.root)
        repeat(2) {
            val process = linux.start(
                listOf("/opt/androidsteam/app/libwayland-probe.so", "driver"),
                listOf("${context.applicationInfo.nativeLibraryDir}:/opt/androidsteam/app", "${graphics.root.path}:/opt/androidsteam/graphics"),
                emptyMap()
            )
            try {
                assertTrue("Linux driver load timed out", process.waitFor(20, TimeUnit.SECONDS))
                val output = process.inputStream.bufferedReader().readText()
                assertEquals(output, 0, process.exitValue())
                assertTrue(output, output.contains("linux-turnip-ready: ICD interface"))
                println(output)
            } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS) }
        }
    }
}
