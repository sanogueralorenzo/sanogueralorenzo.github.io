package com.example.super_overlay.overlay.moonshine

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlin.math.sqrt

class BubbleAudioRecorder(
    private val sampleRateHz: Int = SAMPLE_RATE_HZ,
    private val channelConfig: Int = AudioFormat.CHANNEL_IN_MONO,
    private val audioFormat: Int = AudioFormat.ENCODING_PCM_16BIT
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
        recordingThread = Thread {
            readLoop(bufferSizeShorts)
        }.also { it.start() }
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
        synchronized(lock) { chunks.clear() }
    }

    private fun readLoop(bufferSizeShorts: Int) {
        val buffer = ShortArray(bufferSizeShorts)
        while (isRecording) {
            val record = audioRecord ?: break
            val read = record.read(buffer, 0, buffer.size)
            if (read > 0) {
                val copy = buffer.copyOf(read)
                synchronized(lock) {
                    chunks.add(copy)
                }
                // Keep the CPU from starving the recorder loop on very fast devices.
                computeRms(copy, read)
            }
        }
    }

    private fun stopCaptureAndSnapshot(): List<ShortArray> {
        isRecording = false
        audioRecord?.let { record ->
            try {
                record.stop()
            } catch (_: IllegalStateException) {
                // Ignore stop errors when recording has already ended.
            }
        }
        recordingThread?.join(JOIN_TIMEOUT_MS)
        recordingThread = null
        audioRecord?.release()
        audioRecord = null
        return synchronized(lock) { chunks.toList().also { chunks.clear() } }
    }

    private fun flattenChunks(snapshot: List<ShortArray>): ShortArray {
        val totalSamples = snapshot.sumOf { it.size }
        if (totalSamples == 0) {
            return ShortArray(0)
        }
        val pcm = ShortArray(totalSamples)
        var offset = 0
        for (chunk in snapshot) {
            System.arraycopy(chunk, 0, pcm, offset, chunk.size)
            offset += chunk.size
        }
        return pcm
    }

    @Suppress("UNUSED_PARAMETER")
    private fun computeRms(samples: ShortArray, count: Int): Double {
        if (count <= 0) {
            return 0.0
        }
        var sum = 0.0
        for (i in 0 until count) {
            val v = samples[i].toDouble()
            sum += v * v
        }
        return sqrt(sum / count.toDouble()) / 32768.0
    }

    companion object {
        const val SAMPLE_RATE_HZ = 16_000
        private const val JOIN_TIMEOUT_MS = 800L
    }
}
