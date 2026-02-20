package com.sanogueralorenzo.voice.benchmark

import android.content.Context
import com.sanogueralorenzo.voice.summary.DeterministicComposeRewriter
import com.sanogueralorenzo.voice.summary.LiteRtComposeLlmGate
import com.sanogueralorenzo.voice.summary.LiteRtComposePolicy
import com.sanogueralorenzo.voice.summary.LiteRtSummarizer
import com.sanogueralorenzo.voice.summary.RewriteResult

interface BenchmarkGateway {
    fun runCompose(input: String, promptTemplateOverride: String? = null): RewriteResult
    fun runEdit(original: String, instruction: String): RewriteResult
    fun release() {}
}

class LiteRtBenchmarkGateway(
    context: Context,
    composePolicy: LiteRtComposePolicy,
    deterministicComposeRewriter: DeterministicComposeRewriter,
    composeLlmGate: LiteRtComposeLlmGate
) : BenchmarkGateway {
    private val summarizer = LiteRtSummarizer(
        context = context.applicationContext,
        composePolicy = composePolicy,
        deterministicComposeRewriter = deterministicComposeRewriter,
        composeLlmGate = composeLlmGate
    )

    override fun runCompose(input: String, promptTemplateOverride: String?): RewriteResult {
        return summarizer.summarizeBlocking(
            text = input,
            promptTemplateOverride = promptTemplateOverride
        )
    }

    override fun runEdit(original: String, instruction: String): RewriteResult {
        return summarizer.applyEditInstructionBlocking(
            originalText = original,
            instructionText = instruction
        )
    }

    override fun release() {
        summarizer.release()
    }
}
