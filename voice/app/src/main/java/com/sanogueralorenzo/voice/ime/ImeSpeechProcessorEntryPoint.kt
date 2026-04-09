package com.sanogueralorenzo.voice.ime

import com.sanogueralorenzo.voice.asr.AsrRuntimeStatusStore
import com.sanogueralorenzo.voice.audio.MoonshineTranscriber
import com.sanogueralorenzo.voice.audio.VoiceAudioRecorder
import com.sanogueralorenzo.voice.preferences.PreferencesRepository
import com.sanogueralorenzo.voice.summary.ComposePreLlmRules
import com.sanogueralorenzo.voice.summary.SummaryEngine

/**
 * Public entry point for reusing the IME speech pipeline outside InputMethodService.
 *
 * Pipeline order:
 * 1) ASR output
 * 2) Pre-LLM local rules
 * 3) LLM output
 * 4) Post-LLM local rules
 */
class ImeSpeechProcessorEntryPoint internal constructor(
    private val speechProcessor: SpeechProcessor
) {
    fun process(
        request: ImeSpeechProcessorRequest,
        onShowRewriting: () -> Unit = {},
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
            finalizeMoonshineTranscript = finalizeMoonshineTranscript,
            onShowRewriting = onShowRewriting
        )
        return ImeSpeechProcessorResult(
            transcript = result.transcription.transcript,
            output = result.rewrite.output,
            operation = result.rewrite.operation,
            llmInvoked = result.rewrite.llmInvoked,
            editIntent = result.rewrite.editIntent,
            diagnostics = ImeSpeechProcessorDiagnostics(
                localRulesBeforeLlm = result.rewrite.diagnostics.localRulesBeforeLlm,
                llmOutputText = result.rewrite.diagnostics.llmOutputText,
                localRulesAfterLlm = result.rewrite.diagnostics.localRulesAfterLlm
            )
        )
    }

    companion object {
        fun create(
            moonshineTranscriber: MoonshineTranscriber,
            asrRuntimeStatusStore: AsrRuntimeStatusStore,
            preferencesRepository: PreferencesRepository,
            summaryEngine: SummaryEngine,
            composePreLlmRules: ComposePreLlmRules,
            logTag: String = "VoiceIme"
        ): ImeSpeechProcessorEntryPoint {
            val processor = SpeechProcessor(
                asrStage = AsrStage(
                    moonshineTranscriber = moonshineTranscriber,
                    asrRuntimeStatusStore = asrRuntimeStatusStore,
                    logTag = logTag
                ),
                preLlmRulesStage = PreLlmRulesStage(
                    preferencesRepository = preferencesRepository,
                    summaryEngine = summaryEngine,
                    composePreLlmRules = composePreLlmRules
                ),
                llmStage = LlmStage(
                    summaryEngine = summaryEngine
                ),
                postLlmRulesStage = PostLlmRulesStage()
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

data class ImeSpeechProcessorDiagnostics(
    val localRulesBeforeLlm: List<String>,
    val llmOutputText: String?,
    val localRulesAfterLlm: List<String>
)

data class ImeSpeechProcessorResult(
    val transcript: String,
    val output: String,
    val operation: ImeOperation,
    val llmInvoked: Boolean,
    val editIntent: String?,
    val diagnostics: ImeSpeechProcessorDiagnostics
)
