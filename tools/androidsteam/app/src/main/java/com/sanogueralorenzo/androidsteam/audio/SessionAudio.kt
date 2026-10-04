package com.sanogueralorenzo.androidsteam.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import android.util.Log
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import java.io.Closeable
import java.io.File
import java.io.FileDescriptor
import java.io.RandomAccessFile
import java.util.concurrent.TimeUnit

/** PulseAudio owns Linux mixing; one bounded PCM stream feeds Android output. */
internal class SessionAudio(private val context: Context, private val directory: File) : Closeable {
    private val manager = context.getSystemService(AudioManager::class.java)
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    private val track = AudioTrack.Builder().setAudioAttributes(attributes)
        .setAudioFormat(AudioFormat.Builder().setSampleRate(48_000).setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO).build())
        .setTransferMode(AudioTrack.MODE_STREAM).setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
        .setBufferSizeInBytes(maxOf(3840, AudioTrack.getMinBufferSize(48_000,
            AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT))).build()
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(attributes)
        .setOnAudioFocusChangeListener { change ->
            synchronized(track) {
                if (active && visible) when (change) {
                    AudioManager.AUDIOFOCUS_GAIN -> track.setVolume(1f)
                    AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> track.setVolume(0.2f)
                    else -> track.setVolume(0f)
                }
            }
        }.build()
    private var server: Process? = null
    private var reader: Thread? = null
    private var logger: Thread? = null
    private var descriptor: FileDescriptor? = null
    @Volatile private var active = false
    private var visible = true
    @Volatile var failure: Exception? = null
        private set
    @Volatile var submittedBytes = 0L
        private set
    @Volatile var nonzeroSamples = 0L
        private set
    val playedFrames get() = track.playbackHeadPosition.toLong() and 0xffffffffL
    val underruns get() = track.underrunCount
    val bufferFrames get() = track.bufferSizeInFrames

    fun setVisible(value: Boolean) = synchronized(track) {
        visible = value
        if (active) {
            val granted = value && manager.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            track.setVolume(if (granted) 1f else 0f)
            if (!value) manager.abandonAudioFocusRequest(focus)
        }
        // Continue consuming muted PCM so returning never replays stale audio.
    }

    fun start() {
        check(!active && server == null) { "Audio is already running." }
        check(track.state == AudioTrack.STATE_INITIALIZED) { "Android audio output could not initialize." }
        check(track.setBufferSizeInFrames(960) > 0) { "Android could not configure the playback buffer." }
        check(manager.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            "Audio output is busy. Return to Android Steam and retry."
        }
        val pipe = File(directory, "audio.pcm")
        Os.mkfifo(pipe.path, 0x180) // Private 0600 FIFO, retained until session cleanup.
        val pipeDescriptor = Os.open(pipe.path, OsConstants.O_RDWR or OsConstants.O_NONBLOCK, 0)
        descriptor = pipeDescriptor
        // Linux F_SETPIPE_SZ from the NDK's linux/fcntl.h (absent in OsConstants).
        // Set before PulseAudio samples capacity; 4096 bytes are 21.3ms of PCM.
        check(Os.fcntlInt(pipeDescriptor, 1031, 4096) == 4096) { "Cannot configure the audio pipe buffer." }
        File(directory, "audio.pa").writeText(
            "load-module module-native-protocol-unix auth-anonymous=1 auth-cookie-enabled=0 socket=/run/androidsteam/pulse/native\n" +
            "load-module module-pipe-sink sink_name=Android file=/run/androidsteam/audio.pcm format=s16le rate=48000 channels=2\n" +
            "set-default-sink Android\n")
        val running = LinuxRuntime(context, RuntimeInstaller(context).root).start(
            listOf("/usr/bin/pulseaudio", "-n", "--file=/run/androidsteam/audio.pa", "--daemonize=no",
                "--use-pid-file=no", "--exit-idle-time=-1", "--disable-shm=yes", "--realtime=no",
                "--high-priority=no", "--log-level=warning"),
            listOf("${directory.path}:/run/androidsteam"),
            mapOf("XDG_RUNTIME_DIR" to "/run/androidsteam", "LD_LIBRARY_PATH" to "/usr/lib/pulseaudio"))
        server = running
        logger = Thread({
            try {
                RandomAccessFile(File(context.cacheDir, "steam-audio.log"), "rw").use { log ->
                    log.setLength(0)
                    running.inputStream.bufferedReader().useLines { lines -> lines.forEach { line ->
                        val bytes = (line.take(4096) + "\n").toByteArray()
                        if (log.filePointer + bytes.size > 65_536) { log.setLength(0); log.seek(0) }
                        log.write(bytes)
                    } }
                }
            } catch (e: Exception) { if (active) failure = e }
        }, "Steam audio output").apply { start() }
        val socket = File(directory, "pulse/native")
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
        while ((!pipe.exists() || !socket.exists()) && running.isAlive && System.nanoTime() < deadline) Thread.sleep(20)
        check(running.isAlive && pipe.exists() && socket.exists()) { "Linux audio did not start. See the private audio log and retry." }
        active = true
        track.play()
        reader = Thread({
            try {
                val poll = StructPollfd().apply { fd = pipeDescriptor; events = OsConstants.POLLIN.toShort() }
                val bytes = ByteArray(4096)
                var pending = 0
                while (active) {
                    check(running.isAlive) { "Linux audio stopped. Restart Steam." }
                    if (Os.poll(arrayOf(poll), 200) == 0) continue
                    val received = try { Os.read(pipeDescriptor, bytes, pending, bytes.size - pending) }
                    catch (e: ErrnoException) { if (e.errno == OsConstants.EAGAIN) continue else throw e }
                    check(received > 0) { "Linux audio stream closed. Restart Steam." }
                    val count = pending + received
                    val complete = count - count % 4
                    if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        for (i in 0 until complete step 2) if (bytes[i].toInt() != 0 || bytes[i + 1].toInt() != 0) nonzeroSamples++
                        var written = 0
                        while (written < complete && active) {
                            val sent = track.write(bytes, written, complete - written, AudioTrack.WRITE_BLOCKING)
                            check(sent > 0) { "Android audio output failed ($sent). Restart Steam." }
                            written += sent
                            submittedBytes += sent
                        }
                    }
                    pending = count - complete
                    if (pending > 0) System.arraycopy(bytes, complete, bytes, 0, pending)
                }
            } catch (e: Exception) { if (active) failure = e }
        }, "Steam PCM playback").apply { start() }
    }

    override fun close() {
        synchronized(track) {
            if (active) Log.i("AndroidSteam", "Audio bytes=$submittedBytes played=$playedFrames nonzero=$nonzeroSamples buffer=$bufferFrames underruns=$underruns")
            active = false
            track.pause()
            track.flush()
        }
        manager.abandonAudioFocusRequest(focus)
        server?.destroy()
        try {
            if (server?.waitFor(2, TimeUnit.SECONDS) == false) server?.destroyForcibly()
            reader?.join(2_000)
            logger?.join(2_000)
        } finally {
            descriptor?.let { Os.close(it) }
            synchronized(track) { track.release() }
        }
    }
}
