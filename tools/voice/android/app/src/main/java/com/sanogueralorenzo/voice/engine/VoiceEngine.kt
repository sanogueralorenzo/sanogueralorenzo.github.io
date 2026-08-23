package com.sanogueralorenzo.voice.engine

object VoiceEngine {
    private const val FIELD_SEPARATOR = '\u001F'

    data class PreprocessResult(
        val text: String,
        val changed: Boolean,
        val appliedRuleIds: Set<String>
    )

    enum class EditIntent {
        GENERAL,
        DELETE_ALL,
        REPLACE
    }

    enum class CommandScope {
        ALL,
        FIRST,
        LAST
    }

    enum class CommandKind {
        NO_OP,
        CLEAR_ALL,
        DELETE_TERM,
        REPLACE_TERM,
        UPDATE_NUMBER
    }

    enum class RuleConfidence {
        HIGH,
        LOW
    }

    data class EditInstructionAnalysis(
        val normalizedInstruction: String,
        val intent: EditIntent
    )

    data class DeterministicEditResult(
        val output: String,
        val applied: Boolean,
        val intent: EditIntent,
        val scope: CommandScope,
        val commandKind: CommandKind,
        val matchedCount: Int,
        val ruleConfidence: RuleConfidence,
        val noMatchDetected: Boolean
    )

    fun preprocess(input: String): PreprocessResult {
        val source = input.trim()
        if (source.isBlank()) {
            return PreprocessResult(
                text = "",
                changed = false,
                appliedRuleIds = emptySet()
            )
        }
        val text = NativeVoiceEngine.nativePreprocessText(input)
        val appliedRuleIds = NativeVoiceEngine.nativePreprocessRuleIds(input)
            .split('|')
            .filter { it.isNotBlank() }
            .toCollection(linkedSetOf())
        return PreprocessResult(
            text = text,
            changed = text != source,
            appliedRuleIds = appliedRuleIds
        )
    }

    fun normalizeComposeInput(text: String): String {
        return NativeVoiceEngine.nativeNormalizeComposeInput(text)
    }

    fun normalizeInstructionInput(text: String): String {
        return NativeVoiceEngine.nativeNormalizeInstructionInput(text)
    }

    fun cleanModelOutput(
        text: String,
        bulletMode: Boolean
    ): String {
        return NativeVoiceEngine.nativeCleanModelOutput(
            input = text,
            bulletMode = bulletMode
        )
    }

    fun normalizeComposeOutputText(text: String): String {
        return NativeVoiceEngine.nativeNormalizeComposeOutputText(text)
    }

    fun postprocess(
        originalText: String,
        modelOutput: String,
        listMode: Boolean
    ): String {
        return NativeVoiceEngine.nativeFinalizeComposeOutput(
            originalText = originalText,
            modelOutput = modelOutput,
            listMode = listMode
        )
    }

    fun analyzeInstruction(instructionText: String): EditInstructionAnalysis {
        val fields = NativeVoiceEngine.nativeAnalyzeInstruction(instructionText).split(FIELD_SEPARATOR)
        return EditInstructionAnalysis(
            normalizedInstruction = fields.getOrElse(0) { "" },
            intent = enumValueOf(fields.getOrElse(1) { EditIntent.GENERAL.name })
        )
    }

    fun isStrictEditCommand(instructionText: String): Boolean {
        return NativeVoiceEngine.nativeIsStrictEditCommand(instructionText)
    }

    fun shouldAllowBlankOutput(intent: EditIntent): Boolean {
        return intent == EditIntent.DELETE_ALL
    }

    fun tryApplyDeterministicEdit(
        sourceText: String,
        instructionText: String
    ): DeterministicEditResult? {
        val encoded = NativeVoiceEngine.nativeTryApplyDeterministicEdit(
            sourceText = sourceText,
            instructionText = instructionText
        )
        if (encoded.isBlank()) return null
        val fields = encoded.split(FIELD_SEPARATOR)
        if (fields.size < 8) return null
        return DeterministicEditResult(
            output = fields[0],
            applied = fields[1].toBoolean(),
            intent = enumValueOf(fields[2]),
            scope = enumValueOf(fields[3]),
            commandKind = enumValueOf(fields[4]),
            matchedCount = fields[5].toIntOrNull() ?: 0,
            ruleConfidence = enumValueOf(fields[6]),
            noMatchDetected = fields[7].toBoolean()
        )
    }

    fun looksLikeList(text: String): Boolean {
        return NativeVoiceEngine.nativeLooksLikeList(text)
    }

    fun postReplaceCapitalization(
        sourceText: String,
        instructionText: String,
        editedOutput: String
    ): String {
        return NativeVoiceEngine.nativePostReplaceCapitalization(
            sourceText = sourceText,
            instructionText = instructionText,
            editedOutput = editedOutput
        )
    }
}
