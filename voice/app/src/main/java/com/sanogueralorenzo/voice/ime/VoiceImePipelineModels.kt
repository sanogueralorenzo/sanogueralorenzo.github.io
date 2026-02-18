package com.sanogueralorenzo.voice.ime

import com.sanogueralorenzo.voice.audio.VoiceAudioRecorder

enum class ImeOperation {
    APPEND,
    EDIT
}

internal data class ImePipelineRequest(
    val recorder: VoiceAudioRecorder,
    val sourceTextSnapshot: String,
    val chunkSessionId: Int
)

internal data class ImeTranscriptionResult(
    val transcript: String,
    val path: TranscriptionPath,
    val inputSamples: Int,
    val chunkWaitMs: Long,
    val streamingFinalizeMs: Long,
    val oneShotMs: Long,
    val elapsedMs: Long
)

internal data class ImeRewriteResult(
    val output: String,
    val operation: ImeOperation,
    val attempted: Boolean,
    val applied: Boolean,
    val backend: String?,
    val errorType: String? = null,
    val errorMessage: String? = null,
    val elapsedMs: Long,
    val editIntent: String?
)

internal data class ImePipelineResult(
    val transcription: ImeTranscriptionResult,
    val rewrite: ImeRewriteResult
)

internal data class ImeCommitResult(
    val committed: Boolean,
    val sessionMismatch: Boolean
)
