package com.sanogueralorenzo.voice.ime

import android.os.SystemClock
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.withState

enum class VoiceKeyboardMode {
    IDLE,
    RECORDING,
    PROCESSING
}

enum class VoiceProcessingStage {
    TRANSCRIBING,
    REWRITING
}

enum class TranscriptionPath {
    STREAMING,
    ONE_SHOT_FALLBACK,
    ONE_SHOT_RETRY,
    EMPTY_AUDIO,
    EMPTY_AFTER_ALL_PATHS,
    FAILED
}

data class VoiceDebugMetrics(
    val sessionId: Int,
    val operationMode: ImeOperation,
    val timestampMs: Long,
    val totalMs: Long,
    val transcribeMs: Long,
    val rewriteMs: Long,
    val chunkWaitMs: Long,
    val streamingFinalizeMs: Long,
    val oneShotMs: Long,
    val transcriptionPath: TranscriptionPath,
    val inputSamples: Int,
    val transcriptChars: Int,
    val outputChars: Int,
    val moonshineTranscriptText: String,
    val postLiteRtText: String,
    val rewriteAttempted: Boolean,
    val rewriteApplied: Boolean,
    val rewriteBackend: String?,
    val rewriteErrorType: String?,
    val rewriteError: String?,
    val committed: Boolean,
    val editIntent: String?
)

data class VoiceKeyboardState(
    val mode: VoiceKeyboardMode = VoiceKeyboardMode.IDLE,
    val stage: VoiceProcessingStage = VoiceProcessingStage.TRANSCRIBING,
    val audioLevel: Float = 0f,
    val bottomInsetPx: Int = 0,
    val processingStartedAtMs: Long = 0L,
    val lastDebugMetrics: VoiceDebugMetrics? = null,
    val inlineDebugEnabled: Boolean = false
) : MavericksState

/**
 * Single source of truth for keyboard pill UI state.
 *
 * State transitions are intentionally simple:
 * `IDLE -> RECORDING -> PROCESSING -> IDLE`.
 */
class VoiceKeyboardViewModel(initialState: VoiceKeyboardState) :
    MavericksViewModel<VoiceKeyboardState>(initialState) {

    fun showIdle() {
        setState {
            copy(
                mode = VoiceKeyboardMode.IDLE,
                stage = VoiceProcessingStage.TRANSCRIBING,
                audioLevel = 0f,
                processingStartedAtMs = 0L
            )
        }
    }

    fun showRecording() {
        setState {
            copy(
                mode = VoiceKeyboardMode.RECORDING,
                audioLevel = 0f,
                processingStartedAtMs = 0L
            )
        }
    }

    fun showTranscribing() {
        val now = SystemClock.elapsedRealtime()
        setState {
            copy(
                mode = VoiceKeyboardMode.PROCESSING,
                stage = VoiceProcessingStage.TRANSCRIBING,
                audioLevel = 0f,
                processingStartedAtMs = if (mode == VoiceKeyboardMode.PROCESSING && processingStartedAtMs > 0L) {
                    processingStartedAtMs
                } else {
                    now
                }
            )
        }
    }

    fun showRewriting() {
        val now = SystemClock.elapsedRealtime()
        setState {
            copy(
                mode = VoiceKeyboardMode.PROCESSING,
                stage = VoiceProcessingStage.REWRITING,
                audioLevel = 0f,
                processingStartedAtMs = if (processingStartedAtMs > 0L) processingStartedAtMs else now
            )
        }
    }

    fun updateAudioLevel(rawLevel: Float) {
        setState {
            if (mode != VoiceKeyboardMode.RECORDING) {
                this
            } else {
                copy(audioLevel = rawLevel.coerceIn(0f, 1f))
            }
        }
    }

    fun setBottomInsetPx(px: Int) {
        val clamped = px.coerceAtLeast(0)
        setState {
            if (bottomInsetPx == clamped) this else copy(bottomInsetPx = clamped)
        }
    }

    fun isProcessing(): Boolean {
        var processing = false
        withState(this) { state ->
            processing = state.mode == VoiceKeyboardMode.PROCESSING
        }
        return processing
    }

    fun setDebugMetrics(metrics: VoiceDebugMetrics) {
        setState { copy(lastDebugMetrics = metrics) }
    }

    fun toggleInlineDebug() {
        setState { copy(inlineDebugEnabled = !inlineDebugEnabled) }
    }

    fun isInlineDebugEnabled(): Boolean {
        var enabled = false
        withState(this) { state ->
            enabled = state.inlineDebugEnabled
        }
        return enabled
    }
}
