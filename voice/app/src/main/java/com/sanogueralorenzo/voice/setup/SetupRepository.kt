package com.sanogueralorenzo.voice.setup

internal object SetupRepository {
    data class SetupSnapshot(
        val micGranted: Boolean,
        val voiceImeEnabled: Boolean,
        val keyboardSelected: Boolean,
        val liteRtReady: Boolean,
        val moonshineReady: Boolean,
        val promptReady: Boolean,
        val introDismissed: Boolean
    )

    enum class RequiredStep {
        INTRO,
        MIC_PERMISSION,
        ENABLE_KEYBOARD,
        CHOOSE_KEYBOARD,
        DOWNLOAD_MODELS,
        COMPLETE
    }

    data class MissingSetupItems(
        val micPermission: Boolean,
        val imeEnabled: Boolean,
        val imeSelected: Boolean,
        val liteRtModel: Boolean,
        val moonshineModel: Boolean,
        val promptTemplate: Boolean
    ) {
        val modelsOrPrompt: Boolean
            get() = liteRtModel || moonshineModel || promptTemplate

        val allCoreItemsMissing: Boolean
            get() = micPermission && imeEnabled && liteRtModel && moonshineModel && promptTemplate
    }

    fun requiredStep(snapshot: SetupSnapshot): RequiredStep {
        val missing = missingItems(snapshot)
        if (!snapshot.introDismissed && missing.allCoreItemsMissing) return RequiredStep.INTRO
        if (missing.micPermission) return RequiredStep.MIC_PERMISSION
        if (missing.imeEnabled) return RequiredStep.ENABLE_KEYBOARD
        if (missing.imeSelected) return RequiredStep.CHOOSE_KEYBOARD
        if (missing.modelsOrPrompt) return RequiredStep.DOWNLOAD_MODELS
        return RequiredStep.COMPLETE
    }

    fun shouldShowIntro(snapshot: SetupSnapshot): Boolean {
        return !snapshot.introDismissed && missingItems(snapshot).allCoreItemsMissing
    }

    fun missingItems(snapshot: SetupSnapshot): MissingSetupItems {
        return MissingSetupItems(
            micPermission = !snapshot.micGranted,
            imeEnabled = !snapshot.voiceImeEnabled,
            imeSelected = !snapshot.keyboardSelected,
            liteRtModel = !snapshot.liteRtReady,
            moonshineModel = !snapshot.moonshineReady,
            promptTemplate = !snapshot.promptReady
        )
    }
}
