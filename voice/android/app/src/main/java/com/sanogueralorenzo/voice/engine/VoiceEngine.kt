package com.sanogueralorenzo.voice.engine

object VoiceEngine {
    data class PreprocessResult(
        val text: String,
        val changed: Boolean,
        val appliedRuleIds: Set<String>
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
}

