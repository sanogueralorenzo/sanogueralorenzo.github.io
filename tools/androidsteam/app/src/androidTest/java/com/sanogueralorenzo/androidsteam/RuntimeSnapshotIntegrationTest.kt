package com.sanogueralorenzo.androidsteam

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RuntimeSnapshotIntegrationTest {
    @Test fun freshSnapshotReplacesRuntimeAndRecoversWithoutTouchingHome() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyRuntimeSnapshot") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val archive = File("/data/local/tmp/androidsteam-runtime.tar.xz")
        assertEquals(RuntimeInstaller.ARCHIVE_SIZE, archive.length())
        val digest = MessageDigest.getInstance("SHA-256")
        archive.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        }
        assertEquals(RuntimeInstaller.SHA256, digest.digest().joinToString("") { "%02x".format(it) })
        val root = File(context.filesDir, "runtime-validation")
        val previous = File(context.filesDir, "runtime-validation-previous")
        val preserved = File.createTempFile("runtime-preservation-", ".txt", File(context.filesDir, "home"))
        try {
            preserved.writeText("keep user data")
            val installer = RuntimeInstaller(context, root)
            installer.prepare(archive) { println(it) }
            assertTrue(installer.installed)
            // Exercise an existing runtime replacement, not just fresh extraction.
            assertTrue(File(root, ".androidsteam-runtime").delete())
            installer.prepare(archive) { println(it) }
            assertTrue(installer.installed)
            assertFalse(previous.exists())
            // Recover an interruption after publication but before old-root cleanup.
            val oldCache = File(previous, "certificate-cache").apply { mkdirs() }
            File(oldCache, "old-certificate").writeText("previous runtime")
            assertTrue(oldCache.setWritable(false, true))
            installer.install { fail("A published snapshot must not download again") }
            assertTrue(installer.installed)
            assertFalse(previous.exists())
            val truncated = File(context.cacheDir, "runtime-truncated.tar.xz")
            try {
                archive.inputStream().use { input -> truncated.writeBytes(input.readNBytes(4096)) }
                assertThrows(Exception::class.java) { installer.prepare(truncated) {} }
                assertTrue("A failed replacement must preserve the checked runtime", installer.installed)
            } finally { truncated.delete() }
            try {
                Thread.currentThread().interrupt()
                assertThrows(CancellationException::class.java) { installer.prepare(archive) {} }
            } finally { Thread.interrupted() }
            assertTrue(installer.installed)
            assertTrue(root.renameTo(previous))
            assertTrue("Recover a process interruption between publication moves", RuntimeInstaller(context, root).installed)
            assertFalse(previous.exists())
            assertEquals("keep user data", preserved.readText())
            val process = LinuxRuntime(context, root).startCheck()
            try {
                assertTrue(process.waitFor(10, TimeUnit.SECONDS))
                val output = process.inputStream.bufferedReader().readText()
                assertEquals(output, 0, process.exitValue())
                assertTrue(output, output.contains("aarch64"))
                println(output)
            } finally { process.destroyForcibly() }
            // Retain the verified candidate for the subsequent graphics/game checks.
        } finally { preserved.delete() }
    }
}
