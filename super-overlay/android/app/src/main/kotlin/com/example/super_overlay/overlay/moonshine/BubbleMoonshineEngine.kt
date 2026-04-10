package com.example.super_overlay.overlay.moonshine

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

class BubbleMoonshineEngine(
    context: Context,
    private val onDownloadingChanged: (Boolean) -> Unit
) {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val downloader = MoonshineModelDownloader(appContext)
    private val transcriber = BubbleMoonshineTranscriber(appContext)

    @Volatile
    private var isDownloading: Boolean = false

    fun isModelReady(): Boolean {
        return transcriber.isModelAvailable()
    }

    fun ensureModelReadyAsync(onComplete: (Boolean, String?) -> Unit) {
        if (isModelReady()) {
            mainHandler.post {
                onComplete(true, null)
            }
            return
        }

        if (isDownloading) {
            mainHandler.post {
                onComplete(false, null)
            }
            return
        }

        isDownloading = true
        onDownloadingChanged(true)
        executor.execute {
            val result = downloader.downloadMissingModels()
            isDownloading = false
            onDownloadingChanged(false)
            when (result) {
                MoonshineDownloadResult.Success -> {
                    mainHandler.post {
                        onComplete(true, null)
                    }
                }

                is MoonshineDownloadResult.Failure -> {
                    mainHandler.post {
                        onComplete(false, result.reason)
                    }
                }
            }
        }
    }

    fun transcribeAsync(
        pcm16: ShortArray,
        sampleRateHz: Int,
        onComplete: (String?, String?) -> Unit
    ) {
        executor.execute {
            if (!isModelReady()) {
                mainHandler.post {
                    onComplete(null, "model_not_ready")
                }
                return@execute
            }
            val result = runCatching {
                transcriber.transcribeWithoutStreaming(pcm16, sampleRateHz)
            }
            result
                .onSuccess { text ->
                    mainHandler.post {
                        onComplete(text, null)
                    }
                }
                .onFailure { throwable ->
                    mainHandler.post {
                        onComplete(null, throwable.message ?: "transcribe_failed")
                    }
                }
        }
    }

    fun release() {
        executor.shutdownNow()
        transcriber.release()
    }
}
