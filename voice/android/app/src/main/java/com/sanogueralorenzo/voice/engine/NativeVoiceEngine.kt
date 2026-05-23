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
}

