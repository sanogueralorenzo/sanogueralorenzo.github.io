package com.sanogueralorenzo.voice.benchmark

import android.content.Context
import com.sanogueralorenzo.voice.summary.SummaryEngine
import com.sanogueralorenzo.voice.summary.RewriteResult

interface BenchmarkGateway {
    fun runCompose(input: String, promptTemplateOverride: String? = null): RewriteResult
    fun runEdit(original: String, instruction: String): RewriteResult
    fun release() {}
}

class LiteRtBenchmarkGateway(
    context: Context
) : BenchmarkGateway {
    private val summarizer = SummaryEngine(
        context = context.applicationContext
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
