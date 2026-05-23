package com.sanogueralorenzo.voice.engine

internal object NativeVoiceEngine {
    init {
        System.loadLibrary("voice_engine")
    }

    external fun nativePreprocessText(input: String): String

    external fun nativePreprocessRuleIds(input: String): String

    external fun nativeNormalizeComposeInput(input: String): String

    external fun nativeNormalizeInstructionInput(input: String): String

    external fun nativeCleanModelOutput(
        input: String,
        bulletMode: Boolean
    ): String

    external fun nativeNormalizeComposeOutputText(input: String): String

    external fun nativeFinalizeComposeOutput(
        originalText: String,
        modelOutput: String,
        listMode: Boolean
    ): String

    external fun nativeAnalyzeInstruction(input: String): String

    external fun nativeIsStrictEditCommand(input: String): Boolean

    external fun nativeTryApplyDeterministicEdit(
        sourceText: String,
        instructionText: String
    ): String

    external fun nativeLooksLikeList(input: String): Boolean

    external fun nativePostReplaceCapitalization(
        sourceText: String,
        instructionText: String,
        editedOutput: String
    ): String
}
