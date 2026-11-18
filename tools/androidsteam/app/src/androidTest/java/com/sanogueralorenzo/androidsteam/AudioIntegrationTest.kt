package com.sanogueralorenzo.androidsteam

import android.content.Intent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.sanogueralorenzo.androidsteam.audio.SessionAudio
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import java.io.File
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AudioIntegrationTest {
    @Test fun linuxPulseAudioReachesAndroidOutputAndRestartsCleanly() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("verifyAudio") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertTrue(RuntimeInstaller(context).installed)
        val directory = File(context.cacheDir, "audio-validation")
        ActivityScenario.launch<MainActivity>(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)).use {
            repeat(2) {
                RuntimeArchive.delete(directory)
                assertTrue(directory.mkdirs())
                val audio = SessionAudio(context, directory)
                try {
                    audio.start()
                    val process = LinuxRuntime(context, RuntimeInstaller(context).root).start(
                        listOf("/usr/bin/dash", "-c",
                            "python3 -c 'import math,struct,sys; sys.stdout.buffer.write(b\"\".join(struct.pack(\"<hh\",int(4096*math.sin(i*math.tau*440/48000)),int(4096*math.sin(i*math.tau*440/48000))) for i in range(192000)))' | " +
                                "pacat --raw --format=s16le --rate=48000 --channels=2 --playback"),
                        listOf("${directory.path}:/run/androidsteam"),
                        mapOf("PULSE_SERVER" to "unix:/run/androidsteam/pulse/native", "LD_LIBRARY_PATH" to "/usr/lib/pulseaudio"))
                    try {
                        val warmup = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
                        while (audio.nonzeroSamples < 48_000 && audio.failure == null && System.nanoTime() < warmup) Thread.sleep(20)
                        assertNull(audio.failure)
                        assertTrue("Tone must be actively playing", audio.nonzeroSamples >= 48_000 && process.isAlive)
                        val underruns = audio.underruns
                        val frames = audio.playedFrames
                        Thread.sleep(1_000)
                        assertEquals("No underrun during steady PCM", underruns, audio.underruns)
                        assertTrue("Playback must advance in real time", audio.playedFrames - frames >= 40_000)
                        audio.setVisible(false)
                        Thread.sleep(200)
                        audio.setVisible(true)
                        assertNull(audio.failure)
                        assertTrue("Audio client timed out", process.waitFor(15, TimeUnit.SECONDS))
                        val output = process.inputStream.bufferedReader().readText()
                        assertEquals(output, 0, process.exitValue())
                        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
                        while (audio.playedFrames < 48_000 && audio.failure == null && System.nanoTime() < deadline) Thread.sleep(20)
                        assertNull(audio.failure)
                        assertTrue("Expected real PCM output", audio.submittedBytes >= 192_000 && audio.nonzeroSamples > 48_000)
                        assertTrue("Android must consume the frames", audio.playedFrames >= 48_000)
                        println("PCM bytes=${audio.submittedBytes} played=${audio.playedFrames} nonzero=${audio.nonzeroSamples} buffer=${audio.bufferFrames} underruns=${audio.underruns}")
                    } finally { process.destroyForcibly(); process.waitFor(3, TimeUnit.SECONDS) }
                } finally { audio.close(); RuntimeArchive.delete(directory) }
                assertFalse(directory.exists())
            }
        }
    }
}
