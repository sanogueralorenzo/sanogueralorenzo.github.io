package com.sanogueralorenzo.voice.setup

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.withState
import com.sanogueralorenzo.voice.ime.VoiceProcessingStage

data class OnboardingTutorialUiState(
    val tutorialState: OnboardingTutorialState = OnboardingTutorialStateMachine.initialState()
) : MavericksState

class OnboardingTutorialViewModel(
    initialState: OnboardingTutorialUiState
) : MavericksViewModel<OnboardingTutorialUiState>(initialState) {

    fun onNext() {
        setState {
            copy(tutorialState = OnboardingTutorialStateMachine.onNext(tutorialState))
        }
    }

    fun onPillTap() {
        setState {
            copy(tutorialState = OnboardingTutorialStateMachine.onPillTap(tutorialState))
        }
    }

    fun onEditTap() {
        setState {
            copy(tutorialState = OnboardingTutorialStateMachine.onEditTap(tutorialState))
        }
    }

    fun onSendTap() {
        setState {
            copy(tutorialState = OnboardingTutorialStateMachine.onSendTap(tutorialState))
        }
    }

    fun onFakeRecordingCompleted() {
        setState {
            copy(
                tutorialState = OnboardingTutorialStateMachine.onFakeRecordingCompleted(tutorialState)
            )
        }
    }

    fun onFakeProcessingCompleted() {
        setState {
            copy(
                tutorialState = OnboardingTutorialStateMachine.onFakeProcessingCompleted(tutorialState)
            )
        }
    }

    fun setAudioLevel(level: Float) {
        setState {
            copy(
                tutorialState = tutorialState.copy(audioLevel = level)
            )
        }
    }

    fun setProcessingStage(stage: VoiceProcessingStage) {
        setState {
            copy(
                tutorialState = tutorialState.copy(keyboardStage = stage)
            )
        }
    }

    fun currentStep(): OnboardingTutorialStep {
        var step = OnboardingTutorialStep.WAIT_FOR_PILL_TAP
        withState(this) { state ->
            step = state.tutorialState.step
        }
        return step
    }

    fun canFinish(): Boolean {
        var done = false
        withState(this) { state ->
            done = OnboardingTutorialStateMachine.onDone(state.tutorialState)
        }
        return done
    }
}
