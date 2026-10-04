package com.sanogueralorenzo.androidsteam

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import com.sanogueralorenzo.androidsteam.session.SessionComponents
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class WineIntegrationTest {
    @Test fun relocatedPrivateImagesExecuteWithoutChangingOtherMappings() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifySteam") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val components = SessionComponents(context)
        assertTrue(components.installed)
        val process = LinuxRuntime(context, RuntimeInstaller(context).root).start(
            listOf("/opt/androidsteam/app/libwine-memory-probe.so"),
            listOf("${context.applicationInfo.nativeLibraryDir}:/opt/androidsteam/app",
                "${components.root.path}:/opt/androidsteam/session"),
            mapOf("LD_PRELOAD" to "/opt/androidsteam/session/usr/lib/aarch64-linux-gnu/libsteam-wine-memory.so"))
        try {
            assertTrue("Wine image mapping check timed out", process.waitFor(15, TimeUnit.SECONDS))
            val output = process.inputStream.bufferedReader().readText()
            assertEquals(output, 0, process.exitValue())
            assertTrue(output, output.contains("execution and mapping boundaries verified"))
        } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS) }
    }
}
