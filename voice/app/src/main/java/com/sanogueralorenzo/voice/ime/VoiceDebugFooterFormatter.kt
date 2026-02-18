package com.sanogueralorenzo.voice.ime

object VoiceDebugFooterFormatter {
    fun format(metrics: VoiceDebugMetrics, modeName: String): String {
        val postProcessingMs = (metrics.totalMs - metrics.transcribeMs - metrics.rewriteMs).coerceAtLeast(0L)
        return buildString {
            appendLine("----- VOICE DEBUG -----")
            appendLine("mode: $modeName")
            appendLine("operation_mode: ${metrics.operationMode.name.lowercase()}")
            appendLine("session: ${metrics.sessionId}")
            appendLine("path: ${metrics.transcriptionPath.name}")
            appendLine()
            appendLine("[timings_ms]")
            appendLine("total: ${metrics.totalMs}")
            appendLine("transcribe: ${metrics.transcribeMs}")
            appendLine("chunk_wait: ${metrics.chunkWaitMs}")
            appendLine("stream_finalize: ${metrics.streamingFinalizeMs}")
            appendLine("one_shot: ${metrics.oneShotMs}")
            appendLine("rewrite: ${metrics.rewriteMs}")
            appendLine("post_processing: $postProcessingMs")
            appendLine()
            appendLine("[steps_ms]")
            appendLine("step_1_transcribe: ${metrics.transcribeMs}")
            appendLine("step_2_rewrite: ${metrics.rewriteMs}")
            appendLine("step_3_post_processing: $postProcessingMs")
            appendLine()
            appendLine("[rewrite]")
            appendLine("litert_attempted: ${yesNo(metrics.rewriteAttempted)}")
            appendLine("litert_applied: ${yesNo(metrics.rewriteApplied)}")
            appendLine("litert_backend: ${metrics.rewriteBackend ?: "n/a"}")
            appendLine("litert_error_type: ${metrics.rewriteErrorType ?: "none"}")
            appendLine("litert_error: ${metrics.rewriteError ?: "none"}")
            appendLine("edit_intent: ${metrics.editIntent ?: "none"}")
            appendLine()
            appendLine("[payload]")
            appendLine("input_samples: ${metrics.inputSamples}")
            appendLine("transcript_chars: ${metrics.transcriptChars}")
            appendLine("output_chars: ${metrics.outputChars}")
            appendLine()
            appendLine("[text]")
            appendLine("moonshine_transcript:")
            appendLine(metrics.moonshineTranscriptText)
            appendLine()
            appendLine("post_litert_text:")
            appendLine(metrics.postLiteRtText)
            append("----- END DEBUG -----")
        }
    }

    private fun yesNo(value: Boolean): String = if (value) "yes" else "no"
}
