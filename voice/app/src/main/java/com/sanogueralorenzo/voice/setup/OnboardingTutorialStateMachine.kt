package com.sanogueralorenzo.voice.setup

enum class OnboardingTutorialStep {
    WRITE_WITH_VOICE,
    EDIT_WITH_VOICE,
    SENT_PREVIEW
}

data class OnboardingTutorialState(
    val step: OnboardingTutorialStep,
    val inputText: String,
    val composeSnapshot: String,
    val sentMessage: String
)

object OnboardingTutorialStateMachine {
    fun initialState(): OnboardingTutorialState {
        return OnboardingTutorialState(
            step = OnboardingTutorialStep.WRITE_WITH_VOICE,
            inputText = "",
            composeSnapshot = "",
            sentMessage = ""
        )
    }

    fun onInputChanged(state: OnboardingTutorialState, text: String): OnboardingTutorialState {
        return state.copy(inputText = text)
    }

    fun canAdvance(state: OnboardingTutorialState): Boolean {
        val normalized = state.inputText.trim()
        return when (state.step) {
            OnboardingTutorialStep.WRITE_WITH_VOICE -> normalized.isNotBlank()
            OnboardingTutorialStep.EDIT_WITH_VOICE -> {
                normalized.isNotBlank() && normalized != state.composeSnapshot
            }
            OnboardingTutorialStep.SENT_PREVIEW -> true
        }
    }

    fun onNext(state: OnboardingTutorialState): OnboardingTutorialState {
        if (!canAdvance(state) && state.step != OnboardingTutorialStep.SENT_PREVIEW) return state
        return when (state.step) {
            OnboardingTutorialStep.WRITE_WITH_VOICE -> {
                val snapshot = state.inputText.trim()
                state.copy(
                    step = OnboardingTutorialStep.EDIT_WITH_VOICE,
                    composeSnapshot = snapshot,
                    inputText = snapshot
                )
            }

            OnboardingTutorialStep.EDIT_WITH_VOICE -> {
                val sent = state.inputText.trim()
                state.copy(
                    step = OnboardingTutorialStep.SENT_PREVIEW,
                    sentMessage = sent,
                    inputText = sent
                )
            }

            OnboardingTutorialStep.SENT_PREVIEW -> state
        }
    }

    fun onDone(state: OnboardingTutorialState): Boolean {
        return state.step == OnboardingTutorialStep.SENT_PREVIEW
    }
}
