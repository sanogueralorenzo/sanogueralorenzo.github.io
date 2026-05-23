package com.sanogueralorenzo.voice.summary.rules.pre

import com.sanogueralorenzo.voice.engine.VoiceEngine

/**
 * Compatibility facade for edit rules owned by the shared Rust voice engine.
 */
internal object EditInstructionRules {
    internal enum class EditIntent {
        GENERAL,
        DELETE_ALL,
        REPLACE
    }

    internal enum class CommandScope {
        ALL,
        FIRST,
        LAST
    }

    internal enum class CommandKind {
        NO_OP,
        CLEAR_ALL,
        DELETE_TERM,
        REPLACE_TERM,
        UPDATE_NUMBER
    }

    internal enum class RuleConfidence {
        HIGH,
        LOW
    }

    internal data class EditInstructionAnalysis(
        val normalizedInstruction: String,
        val intent: EditIntent
    )

    internal data class DeterministicEditResult(
        val output: String,
        val applied: Boolean,
        val intent: EditIntent,
        val scope: CommandScope,
        val commandKind: CommandKind,
        val matchedCount: Int,
        val ruleConfidence: RuleConfidence,
        val noMatchDetected: Boolean
    )

    fun analyzeInstruction(instructionText: String): EditInstructionAnalysis {
        val result = VoiceEngine.analyzeInstruction(instructionText)
        return EditInstructionAnalysis(
            normalizedInstruction = result.normalizedInstruction,
            intent = EditIntent.valueOf(result.intent.name)
        )
    }

    fun isStrictEditCommand(instructionText: String): Boolean {
        return VoiceEngine.isStrictEditCommand(instructionText)
    }

    fun shouldAllowBlankOutput(intent: EditIntent): Boolean {
        return VoiceEngine.shouldAllowBlankOutput(VoiceEngine.EditIntent.valueOf(intent.name))
    }

    fun tryApplyDeterministicEdit(
        sourceText: String,
        instructionText: String
    ): DeterministicEditResult? {
        val result = VoiceEngine.tryApplyDeterministicEdit(
            sourceText = sourceText,
            instructionText = instructionText
        ) ?: return null
        return DeterministicEditResult(
            output = result.output,
            applied = result.applied,
            intent = EditIntent.valueOf(result.intent.name),
            scope = CommandScope.valueOf(result.scope.name),
            commandKind = CommandKind.valueOf(result.commandKind.name),
            matchedCount = result.matchedCount,
            ruleConfidence = RuleConfidence.valueOf(result.ruleConfidence.name),
            noMatchDetected = result.noMatchDetected
        )
    }

    fun looksLikeList(text: String): Boolean {
        return VoiceEngine.looksLikeList(text)
    }
}
