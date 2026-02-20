package com.sanogueralorenzo.voice.benchmark

import android.content.Context
import com.sanogueralorenzo.voice.summary.ComposePreLlmRules
import com.sanogueralorenzo.voice.summary.ComposeLlmGate
import com.sanogueralorenzo.voice.summary.ComposePostLlmRules
import com.sanogueralorenzo.voice.summary.SummaryEngine
import com.sanogueralorenzo.voice.summary.RewriteResult

interface BenchmarkGateway {
    fun runCompose(input: String, promptTemplateOverride: String? = null): RewriteResult
    fun runEdit(original: String, instruction: String): RewriteResult
    fun release() {}
}

class LiteRtBenchmarkGateway(
    context: Context,
    composePolicy: ComposePostLlmRules,
    composePreLlmRules: ComposePreLlmRules,
    composeLlmGate: ComposeLlmGate
) : BenchmarkGateway {
    private val summarizer = SummaryEngine(
        context = context.applicationContext,
        composePolicy = composePolicy,
        composePreLlmRules = composePreLlmRules,
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
