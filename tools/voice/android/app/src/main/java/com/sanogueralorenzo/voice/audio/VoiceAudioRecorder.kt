package com.sanogueralorenzo.voice.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.SystemClock
import kotlin.math.sqrt

/**
 * Captures microphone PCM, emits level updates for UI, and forwards frames to Moonshine.
 */
class VoiceAudioRecorder(
    private val sampleRateHz: Int = SAMPLE_RATE_HZ,
    private val channelConfig: Int = AudioFormat.CHANNEL_IN_MONO,
    private val audioFormat: Int = AudioFormat.ENCODING_PCM_16BIT,
    private val onLevelChanged: ((Float) -> Unit)? = null,
    private val onAudioFrame: ((ShortArray) -> Unit)? = null
) {
    @Volatile
    private var isRecording = false
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private val chunks = ArrayList<ShortArray>()
    private val lock = Any()

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        val minBufferBytes = AudioRecord.getMinBufferSize(sampleRateHz, channelConfig, audioFormat)
        if (minBufferBytes == AudioRecord.ERROR || minBufferBytes == AudioRecord.ERROR_BAD_VALUE) {
            return false
        }

        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRateHz,
                channelConfig,
                audioFormat,
                minBufferBytes
            )
        } catch (_: SecurityException) {
            return false
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            return false
        }

        audioRecord = record
        isRecording = true
        try {
            record.startRecording()
        } catch (_: SecurityException) {
            isRecording = false
            audioRecord = null
            record.release()
            return false
        } catch (_: IllegalStateException) {
            isRecording = false
            audioRecord = null
            record.release()
            return false
        }
        val bufferSizeShorts = (minBufferBytes / 2).coerceAtLeast(1)
        recordingThread = Thread { readLoop(bufferSizeShorts) }.also { it.start() }
        return true
    }

    fun stopAndGetPcm(): ShortArray {
        val snapshot = stopCaptureAndSnapshot()
        return flattenChunks(snapshot)
    }

    fun release() {
        isRecording = false
        recordingThread?.join(JOIN_TIMEOUT_MS)
        recordingThread = null
        audioRecord?.release()
        audioRecord = null
        onLevelChanged?.invoke(0f)
        synchronized(lock) { chunks.clear() }
    }

    private fun readLoop(bufferSizeShorts: Int) {
        val buffer = ShortArray(bufferSizeShorts)
        var smoothed = 0f
        var lastEmitAt = 0L
        while (isRecording) {
            val record = audioRecord ?: break
            val read = record.read(buffer, 0, buffer.size)
            if (read > 0) {
                val copy = buffer.copyOf(read)
                synchronized(lock) {
                    chunks.add(copy)
                }
                onAudioFrame?.invoke(copy)
                val rms = computeRms(copy, read)
                val uiLevel = (rms * LEVEL_SCALE).toFloat().coerceIn(0f, 1f)
                smoothed = (smoothed * 0.75f) + (uiLevel * 0.25f)
                val now = SystemClock.uptimeMillis()
                if ((now - lastEmitAt) >= LEVEL_EMIT_MS) {
                    lastEmitAt = now
                    onLevelChanged?.invoke(smoothed.coerceIn(0f, 1f))
                }
            }
        }
    }

    private fun computeRms(samples: ShortArray, count: Int): Double {
        if (count <= 0) return 0.0
        var sum = 0.0
        for (i in 0 until count) {
            val v = samples[i].toDouble()
            sum += v * v
        }
        return sqrt(sum / count.toDouble()) / 32768.0
    }

    private fun stopCaptureAndSnapshot(): List<ShortArray> {
        isRecording = false
        audioRecord?.let { record ->
            try {
                record.stop()
            } catch (_: IllegalStateException) {
                // Ignore stop errors when recording hasn't started cleanly.
            }
        }
        recordingThread?.join(JOIN_TIMEOUT_MS)
        recordingThread = null
        audioRecord?.release()
        audioRecord = null
        onLevelChanged?.invoke(0f)
        return synchronized(lock) { chunks.toList().also { chunks.clear() } }
    }

    private fun flattenChunks(snapshot: List<ShortArray>): ShortArray {
        val totalSamples = snapshot.sumOf { it.size }
        if (totalSamples == 0) return ShortArray(0)
        val pcm = ShortArray(totalSamples)
        var offset = 0
        for (chunk in snapshot) {
            System.arraycopy(chunk, 0, pcm, offset, chunk.size)
            offset += chunk.size
        }
        return pcm
    }

    companion object {
        const val SAMPLE_RATE_HZ = 16000
        private const val JOIN_TIMEOUT_MS = 800L
        private const val LEVEL_EMIT_MS = 40L
        private const val LEVEL_SCALE = 3.5
    }
}
