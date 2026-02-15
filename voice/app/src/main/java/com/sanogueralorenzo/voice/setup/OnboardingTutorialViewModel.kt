package com.sanogueralorenzo.voice.setup

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.withState

data class OnboardingTutorialUiState(
    val tutorialState: OnboardingTutorialState = OnboardingTutorialStateMachine.initialState()
) : MavericksState

class OnboardingTutorialViewModel(
    initialState: OnboardingTutorialUiState
) : MavericksViewModel<OnboardingTutorialUiState>(initialState) {

    fun onInputChanged(text: String) {
        setState {
            copy(tutorialState = OnboardingTutorialStateMachine.onInputChanged(tutorialState, text))
        }
    }

    fun onNext() {
        setState {
            copy(tutorialState = OnboardingTutorialStateMachine.onNext(tutorialState))
        }
    }

    fun canAdvance(): Boolean {
        return withState(this) { state ->
            OnboardingTutorialStateMachine.canAdvance(state.tutorialState)
        }
    }

    fun isSentPreview(): Boolean {
        return withState(this) { state ->
            state.tutorialState.step == OnboardingTutorialStep.SENT_PREVIEW
        }
    }

    fun canFinish(): Boolean {
        return withState(this) { state ->
            OnboardingTutorialStateMachine.onDone(state.tutorialState)
        }
    }
}
