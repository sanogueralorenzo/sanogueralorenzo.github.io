package com.sanogueralorenzo.voice.setup

import android.content.Context
import com.sanogueralorenzo.voice.summary.LiteRtSummarizer
import com.sanogueralorenzo.voice.summary.RewriteResult

interface PromptBenchmarkGateway {
    fun runCompose(input: String, promptTemplateOverride: String? = null): RewriteResult
    fun runEdit(original: String, instruction: String): RewriteResult
}

class LiteRtPromptBenchmarkGateway(context: Context) : PromptBenchmarkGateway {
    private val summarizer = LiteRtSummarizer(context.applicationContext)

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

    fun release() {
        summarizer.release()
    }
}
