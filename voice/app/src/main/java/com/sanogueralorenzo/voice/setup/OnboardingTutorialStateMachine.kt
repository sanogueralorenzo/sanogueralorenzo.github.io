package com.sanogueralorenzo.voice.setup

import com.sanogueralorenzo.voice.ime.VoiceKeyboardMode
import com.sanogueralorenzo.voice.ime.VoiceKeyboardState
import com.sanogueralorenzo.voice.ime.VoiceProcessingStage

enum class OnboardingTutorialStep {
    INTRO,
    WAIT_FOR_PILL_TAP,
    FAKE_RECORDING_COMPOSE,
    FAKE_PROCESSING_COMPOSE,
    WAIT_FOR_EDIT_TAP,
    FAKE_RECORDING_EDIT,
    FAKE_PROCESSING_EDIT,
    FINAL_REVIEW
}

enum class OnboardingSpeechCue {
    NONE,
    COMPOSE_REQUEST,
    EDIT_REQUEST
}

enum class OnboardingOutputVariant {
    NONE,
    INITIAL_LIST,
    FINAL_LIST
}

data class OnboardingTutorialState(
    val step: OnboardingTutorialStep,
    val nextEnabled: Boolean,
    val keyboardMode: VoiceKeyboardMode,
    val keyboardStage: VoiceProcessingStage,
    val audioLevel: Float,
    val showEditButton: Boolean,
    val speechCue: OnboardingSpeechCue,
    val outputVariant: OnboardingOutputVariant
)

object OnboardingTutorialStateMachine {
    fun initialState(): OnboardingTutorialState {
        return OnboardingTutorialState(
            step = OnboardingTutorialStep.INTRO,
            nextEnabled = true,
            keyboardMode = VoiceKeyboardMode.IDLE,
            keyboardStage = VoiceProcessingStage.TRANSCRIBING,
            audioLevel = 0f,
            showEditButton = false,
            speechCue = OnboardingSpeechCue.NONE,
            outputVariant = OnboardingOutputVariant.NONE
        )
    }

    fun onNext(state: OnboardingTutorialState): OnboardingTutorialState {
        return when (state.step) {
            OnboardingTutorialStep.INTRO -> state.copy(
                step = OnboardingTutorialStep.WAIT_FOR_PILL_TAP,
                nextEnabled = false,
                keyboardMode = VoiceKeyboardMode.IDLE,
                audioLevel = 0f,
                showEditButton = false,
                speechCue = OnboardingSpeechCue.NONE,
                outputVariant = OnboardingOutputVariant.NONE
            )

            OnboardingTutorialStep.WAIT_FOR_PILL_TAP -> {
                if (!state.nextEnabled) return state
                state.copy(
                    step = OnboardingTutorialStep.FAKE_RECORDING_COMPOSE,
                    nextEnabled = false,
                    keyboardMode = VoiceKeyboardMode.RECORDING,
                    keyboardStage = VoiceProcessingStage.TRANSCRIBING,
                    audioLevel = 0.2f,
                    showEditButton = false,
                    speechCue = OnboardingSpeechCue.NONE
                )
            }

            OnboardingTutorialStep.FAKE_RECORDING_COMPOSE -> {
                if (!state.nextEnabled) return state
                state.copy(
                    step = OnboardingTutorialStep.FAKE_PROCESSING_COMPOSE,
                    nextEnabled = false,
                    keyboardMode = VoiceKeyboardMode.PROCESSING,
                    keyboardStage = VoiceProcessingStage.TRANSCRIBING,
                    audioLevel = 0f,
                    showEditButton = false
                )
            }

            OnboardingTutorialStep.FAKE_PROCESSING_COMPOSE -> {
                if (!state.nextEnabled) return state
                state.copy(
                    step = OnboardingTutorialStep.WAIT_FOR_EDIT_TAP,
                    nextEnabled = false,
                    keyboardMode = VoiceKeyboardMode.IDLE,
                    keyboardStage = VoiceProcessingStage.TRANSCRIBING,
                    audioLevel = 0f,
                    showEditButton = true,
                    outputVariant = OnboardingOutputVariant.INITIAL_LIST
                )
            }

            OnboardingTutorialStep.WAIT_FOR_EDIT_TAP -> {
                if (!state.nextEnabled) return state
                state.copy(
                    step = OnboardingTutorialStep.FAKE_RECORDING_EDIT,
                    nextEnabled = false,
                    keyboardMode = VoiceKeyboardMode.RECORDING,
                    keyboardStage = VoiceProcessingStage.TRANSCRIBING,
                    audioLevel = 0.2f,
                    showEditButton = true
                )
            }

            OnboardingTutorialStep.FAKE_RECORDING_EDIT -> {
                if (!state.nextEnabled) return state
                state.copy(
                    step = OnboardingTutorialStep.FAKE_PROCESSING_EDIT,
                    nextEnabled = false,
                    keyboardMode = VoiceKeyboardMode.PROCESSING,
                    keyboardStage = VoiceProcessingStage.TRANSCRIBING,
                    audioLevel = 0f,
                    showEditButton = true
                )
            }

            OnboardingTutorialStep.FAKE_PROCESSING_EDIT -> {
                if (!state.nextEnabled) return state
                state.copy(
                    step = OnboardingTutorialStep.FINAL_REVIEW,
                    nextEnabled = true,
                    keyboardMode = VoiceKeyboardMode.IDLE,
                    keyboardStage = VoiceProcessingStage.TRANSCRIBING,
                    audioLevel = 0f,
                    showEditButton = true,
                    outputVariant = OnboardingOutputVariant.FINAL_LIST
                )
            }

            OnboardingTutorialStep.FINAL_REVIEW -> state
        }
    }

    fun onPillTap(state: OnboardingTutorialState): OnboardingTutorialState {
        if (state.step != OnboardingTutorialStep.WAIT_FOR_PILL_TAP) return state
        return state.copy(
            step = OnboardingTutorialStep.FAKE_RECORDING_COMPOSE,
            nextEnabled = false,
            keyboardMode = VoiceKeyboardMode.RECORDING,
            keyboardStage = VoiceProcessingStage.TRANSCRIBING,
            audioLevel = 0.2f,
            showEditButton = false,
            speechCue = OnboardingSpeechCue.NONE
        )
    }

    fun onEditTap(state: OnboardingTutorialState): OnboardingTutorialState {
        if (state.step != OnboardingTutorialStep.WAIT_FOR_EDIT_TAP) return state
        return state.copy(
            step = OnboardingTutorialStep.FAKE_RECORDING_EDIT,
            nextEnabled = false,
            keyboardMode = VoiceKeyboardMode.RECORDING,
            keyboardStage = VoiceProcessingStage.TRANSCRIBING,
            audioLevel = 0.2f,
            showEditButton = true,
            speechCue = OnboardingSpeechCue.NONE
        )
    }

    fun onFakeRecordingCompleted(state: OnboardingTutorialState): OnboardingTutorialState {
        return when (state.step) {
            OnboardingTutorialStep.FAKE_RECORDING_COMPOSE -> state.copy(
                nextEnabled = true,
                audioLevel = 0.35f,
                speechCue = OnboardingSpeechCue.COMPOSE_REQUEST
            )

            OnboardingTutorialStep.FAKE_RECORDING_EDIT -> state.copy(
                nextEnabled = true,
                audioLevel = 0.35f,
                speechCue = OnboardingSpeechCue.EDIT_REQUEST
            )

            else -> state
        }
    }

    fun onFakeProcessingCompleted(state: OnboardingTutorialState): OnboardingTutorialState {
        return when (state.step) {
            OnboardingTutorialStep.FAKE_PROCESSING_COMPOSE -> state.copy(
                nextEnabled = true,
                outputVariant = OnboardingOutputVariant.INITIAL_LIST
            )

            OnboardingTutorialStep.FAKE_PROCESSING_EDIT -> state.copy(
                nextEnabled = true,
                outputVariant = OnboardingOutputVariant.FINAL_LIST
            )

            else -> state
        }
    }

    fun onDone(state: OnboardingTutorialState): Boolean {
        return state.step == OnboardingTutorialStep.FINAL_REVIEW
    }

    fun toKeyboardState(state: OnboardingTutorialState): VoiceKeyboardState {
        return VoiceKeyboardState(
            mode = state.keyboardMode,
            stage = state.keyboardStage,
            audioLevel = state.audioLevel,
            canEditCurrentInput = state.showEditButton,
            inlineDebugEnabled = false
        )
    }
}
