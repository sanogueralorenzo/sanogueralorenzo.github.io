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
    SUMMARIZING
}

enum class TranscriptionPath {
    STREAMING,
    ONE_SHOT_FALLBACK,
    EMPTY_AUDIO,
    EMPTY_AFTER_ALL_PATHS,
    FAILED
}

data class VoiceDebugMetrics(
    val sessionId: Int,
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
    val rewriteAttempted: Boolean,
    val rewriteApplied: Boolean,
    val rewriteFallbackReason: String?,
    val committed: Boolean
)

data class VoiceKeyboardState(
    val mode: VoiceKeyboardMode = VoiceKeyboardMode.IDLE,
    val stage: VoiceProcessingStage = VoiceProcessingStage.TRANSCRIBING,
    val audioLevel: Float = 0f,
    val processingStartedAtMs: Long = 0L,
    val canEditCurrentInput: Boolean = false,
    val lastDebugMetrics: VoiceDebugMetrics? = null,
    val debugDialogVisible: Boolean = false
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
                processingStartedAtMs = 0L,
                debugDialogVisible = false
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
                debugDialogVisible = false,
                processingStartedAtMs = if (mode == VoiceKeyboardMode.PROCESSING && processingStartedAtMs > 0L) {
                    processingStartedAtMs
                } else {
                    now
                }
            )
        }
    }

    fun showSummarizing() {
        val now = SystemClock.elapsedRealtime()
        setState {
            copy(
                mode = VoiceKeyboardMode.PROCESSING,
                stage = VoiceProcessingStage.SUMMARIZING,
                audioLevel = 0f,
                debugDialogVisible = false,
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

    fun isProcessing(): Boolean {
        var processing = false
        withState(this) { state ->
            processing = state.mode == VoiceKeyboardMode.PROCESSING
        }
        return processing
    }

    fun setDebugMetrics(metrics: VoiceDebugMetrics) {
        setState {
            copy(
                lastDebugMetrics = metrics,
                debugDialogVisible = false
            )
        }
    }

    fun setCanEditCurrentInput(canEdit: Boolean) {
        setState { copy(canEditCurrentInput = canEdit) }
    }

    fun showDebugDialog() {
        setState {
            if (lastDebugMetrics == null || mode != VoiceKeyboardMode.IDLE) {
                this
            } else {
                copy(debugDialogVisible = true)
            }
        }
    }

    fun hideDebugDialog() {
        setState { copy(debugDialogVisible = false) }
    }
}
