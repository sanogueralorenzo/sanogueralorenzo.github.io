package com.sanogueralorenzo.voice.ime

import com.sanogueralorenzo.voice.asr.AsrRuntimeStatusStore
import com.sanogueralorenzo.voice.audio.MoonshineTranscriber
import com.sanogueralorenzo.voice.audio.VoiceAudioRecorder

/**
 * Public entry point for reusing the IME speech pipeline outside InputMethodService.
 *
 * Pipeline order: ASR output, then deterministic edit or append.
 */
class ImeSpeechProcessorEntryPoint internal constructor(
    private val speechProcessor: SpeechProcessor
) {
    fun process(
        request: ImeSpeechProcessorRequest,
        awaitChunkSessionQuiescence: (Int) -> Unit = {},
        finalizeMoonshineTranscript: (Int) -> String = { "" }
    ): ImeSpeechProcessorResult {
        val result = speechProcessor.process(
            request = ImePipelineRequest(
                recorder = request.recorder,
                sourceTextSnapshot = request.sourceTextSnapshot,
                chunkSessionId = request.chunkSessionId
            ),
            awaitChunkSessionQuiescence = awaitChunkSessionQuiescence,
            finalizeMoonshineTranscript = finalizeMoonshineTranscript
        )
        return ImeSpeechProcessorResult(
            transcript = result.transcription.transcript,
            output = result.rewrite.output,
            operation = result.rewrite.operation,
            editIntent = result.rewrite.editIntent
        )
    }

    companion object {
        fun create(
            moonshineTranscriber: MoonshineTranscriber,
            asrRuntimeStatusStore: AsrRuntimeStatusStore,
            logTag: String = "VoiceIme"
        ): ImeSpeechProcessorEntryPoint {
            val processor = SpeechProcessor(
                asrStage = AsrStage(
                    moonshineTranscriber = moonshineTranscriber,
                    asrRuntimeStatusStore = asrRuntimeStatusStore,
                    logTag = logTag
                ),
                textStage = TextStage()
            )
            return ImeSpeechProcessorEntryPoint(processor)
        }
    }
}

data class ImeSpeechProcessorRequest(
    val recorder: VoiceAudioRecorder,
    val sourceTextSnapshot: String,
    val chunkSessionId: Int = 0
)

data class ImeSpeechProcessorResult(
    val transcript: String,
    val output: String,
    val operation: ImeOperation,
    val editIntent: String?
)
