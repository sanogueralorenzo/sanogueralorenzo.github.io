package com.sanogueralorenzo.voice.keyboard

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.SystemClock
import kotlin.math.sqrt

/** Captures the keyboard's microphone audio and drives its level visualizer. */
internal class KeyboardAudioRecorder(
    private val onLevelChanged: (Float) -> Unit,
    private val onAudioFrame: (ShortArray) -> Unit
) {
    @Volatile
    private var recording = false
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private val chunks = ArrayList<ShortArray>()
    private val lock = Any()

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        val minBufferBytes = AudioRecord.getMinBufferSize(
            SAMPLE_RATE_HZ,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        if (minBufferBytes == AudioRecord.ERROR || minBufferBytes == AudioRecord.ERROR_BAD_VALUE) {
            return false
        }
        val recorder = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                SAMPLE_RATE_HZ,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minBufferBytes
            )
        } catch (_: SecurityException) {
            return false
        }
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return false
        }
        audioRecord = recorder
        recording = true
        try {
            recorder.startRecording()
        } catch (_: SecurityException) {
            releaseFailedStart(recorder)
            return false
        } catch (_: IllegalStateException) {
            releaseFailedStart(recorder)
            return false
        }
        val bufferSizeShorts = (minBufferBytes / 2).coerceAtLeast(1)
        recordingThread = Thread(
            { readLoop(bufferSizeShorts) },
            "voice-keyboard-recorder"
        ).also(Thread::start)
        return true
    }

    fun stopAndGetPcm(): ShortArray {
        recording = false
        audioRecord?.let { recorder ->
            runCatching { recorder.stop() }
        }
        recordingThread?.join(JOIN_TIMEOUT_MS)
        recordingThread = null
        audioRecord?.release()
        audioRecord = null
        onLevelChanged(0f)
        val snapshot = synchronized(lock) { chunks.toList().also { chunks.clear() } }
        val totalSamples = snapshot.sumOf(ShortArray::size)
        if (totalSamples == 0) return ShortArray(0)
        return ShortArray(totalSamples).also { pcm ->
            var offset = 0
            snapshot.forEach { chunk ->
                System.arraycopy(chunk, 0, pcm, offset, chunk.size)
                offset += chunk.size
            }
        }
    }

    private fun readLoop(bufferSizeShorts: Int) {
        val buffer = ShortArray(bufferSizeShorts)
        var smoothedLevel = 0f
        var lastLevelAt = 0L
        while (recording) {
            val recorder = audioRecord ?: break
            val read = recorder.read(buffer, 0, buffer.size)
            if (read <= 0) continue
            val frame = buffer.copyOf(read)
            synchronized(lock) { chunks.add(frame) }
            onAudioFrame(frame)
            val rms = computeRms(frame)
            val level = (rms * LEVEL_SCALE).toFloat().coerceIn(0f, 1f)
            smoothedLevel = smoothedLevel * 0.75f + level * 0.25f
            val now = SystemClock.uptimeMillis()
            if (now - lastLevelAt >= LEVEL_EMIT_MS) {
                lastLevelAt = now
                onLevelChanged(smoothedLevel.coerceIn(0f, 1f))
            }
        }
    }

    private fun computeRms(samples: ShortArray): Double {
        if (samples.isEmpty()) return 0.0
        var sum = 0.0
        samples.forEach { sample ->
            val value = sample.toDouble()
            sum += value * value
        }
        return sqrt(sum / samples.size) / 32768.0
    }

    private fun releaseFailedStart(recorder: AudioRecord) {
        recording = false
        audioRecord = null
        recorder.release()
    }

    companion object {
        const val SAMPLE_RATE_HZ = 16_000
        private const val JOIN_TIMEOUT_MS = 800L
        private const val LEVEL_EMIT_MS = 40L
        private const val LEVEL_SCALE = 3.5
    }
}
