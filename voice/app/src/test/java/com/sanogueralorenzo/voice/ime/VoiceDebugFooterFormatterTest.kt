package com.sanogueralorenzo.voice.ime

import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceDebugFooterFormatterTest {
    @Test
    fun format_containsCoreFields() {
        val metrics = VoiceDebugMetrics(
            sessionId = 7,
            operationMode = ImeOperation.EDIT,
            timestampMs = 1700000000000L,
            totalMs = 1400L,
            transcribeMs = 900L,
            rewriteMs = 300L,
            chunkWaitMs = 120L,
            streamingFinalizeMs = 210L,
            oneShotMs = 0L,
            transcriptionPath = TranscriptionPath.STREAMING,
            inputSamples = 16000,
            transcriptChars = 42,
            outputChars = 35,
            moonshineTranscriptText = "before",
            postLiteRtText = "after",
            rewriteAttempted = true,
            rewriteApplied = true,
            rewriteBackend = "GPU",
            rewriteErrorType = null,
            rewriteError = null,
            committed = true,
            editIntent = "REPLACE_TERM"
        )

        val footer = VoiceDebugFooterFormatter.format(metrics, "AUTO")
        assertTrue(footer.contains("mode: AUTO"))
        assertTrue(footer.contains("operation_mode: edit"))
        assertTrue(footer.contains("session: 7"))
        assertTrue(footer.contains("litert_backend: GPU"))
        assertTrue(footer.contains("litert_error_type: none"))
        assertTrue(footer.contains("moonshine_transcript:"))
        assertTrue(footer.contains("post_litert_text:"))
        assertTrue(footer.contains("----- END DEBUG -----"))
    }
}
