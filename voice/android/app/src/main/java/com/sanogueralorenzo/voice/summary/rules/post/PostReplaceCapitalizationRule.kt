package com.sanogueralorenzo.voice.summary.rules.post

import com.sanogueralorenzo.voice.engine.VoiceEngine

/**
 * Compatibility facade for replacement casing owned by the shared Rust voice engine.
 */
internal class PostReplaceCapitalizationRule {
    fun apply(
        sourceText: String,
        instructionText: String,
        editedOutput: String
    ): String {
        return VoiceEngine.postReplaceCapitalization(
            sourceText = sourceText,
            instructionText = instructionText,
            editedOutput = editedOutput
        )
    }
}
