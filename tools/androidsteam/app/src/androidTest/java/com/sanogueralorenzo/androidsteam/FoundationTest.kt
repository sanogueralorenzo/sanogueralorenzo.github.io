package com.sanogueralorenzo.androidsteam

import android.content.Intent
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FoundationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext

    @Test fun launchesWithHonestRuntimeStatus() {
        val activity = instrumentation.startActivitySync(Intent(context, SetupActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        try {
            instrumentation.runOnMainSync {
                assertEquals(context.getString(R.string.development_notice), activity.findViewById<TextView>(R.id.development_notice).text.toString())
                assertTrue(activity.findViewById<TextView>(R.id.device).text.isNotBlank())
            }
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }

    @Test fun packagedExecutableRuns() {
        checkExecution(File(context.applicationInfo.nativeLibraryDir, "libexecution-probe.so"))
    }

    @Test fun writableExecutableFollowsTargetPolicy() {
        val executable = File(context.filesDir, "execution-probe")
        try {
            File(context.applicationInfo.nativeLibraryDir, "libexecution-probe.so").copyTo(executable, overwrite = true)
            assertTrue(executable.setExecutable(true, true))
            assertEquals(36, context.applicationInfo.targetSdkVersion)
            val failure = assertThrows(java.io.IOException::class.java) { ProcessBuilder(executable.path).start() }
            assertTrue(failure.message.orEmpty().contains("error=13"))
        } finally {
            executable.delete()
        }
    }

    @Test fun packagedProotLoadsWritableExecutable() {
        val executable = File(context.filesDir, "proot-execution-probe")
        val native = context.applicationInfo.nativeLibraryDir
        try {
            File(native, "libexecution-probe.so").copyTo(executable, overwrite = true)
            executable.setExecutable(true, true)
            val builder = ProcessBuilder("$native/libproot.so", "-r", "/", executable.path)
            builder.environment()["PROOT_LOADER"] = "$native/libproot-loader.so"
            builder.environment()["PROOT_TMP_DIR"] = context.cacheDir.path
            checkExecution(builder)
        } finally {
            executable.delete()
        }
    }

    private fun checkExecution(executable: File) = checkExecution(ProcessBuilder(executable.path))

    private fun checkExecution(builder: ProcessBuilder) {
        val process = builder.redirectErrorStream(true).start()
        try {
            assertTrue("Executable timed out", process.waitFor(5, TimeUnit.SECONDS))
            val output = process.inputStream.bufferedReader().use { it.readText() }
            assertEquals(output, 0, process.exitValue())
            assertEquals("androidsteam-execution-ok", output.trim())
        } finally {
            process.destroyForcibly()
        }
    }
}
