package com.sanogueralorenzo.voice.setup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OnboardingTutorialStateMachineTest {
    @Test
    fun cannotAdvancePillStepUntilPillIsTapped() {
        var state = OnboardingTutorialStateMachine.initialState()
        assertEquals(OnboardingTutorialStep.WAIT_FOR_PILL_TAP, state.step)
        assertFalse(state.nextEnabled)

        val blocked = OnboardingTutorialStateMachine.onNext(state)
        assertEquals(OnboardingTutorialStep.WAIT_FOR_PILL_TAP, blocked.step)

        state = OnboardingTutorialStateMachine.onPillTap(state)
        assertEquals(OnboardingTutorialStep.FAKE_RECORDING_COMPOSE, state.step)
    }

    @Test
    fun composeFlowProducesInitialListOutput() {
        var state = OnboardingTutorialStateMachine.initialState()
        state = OnboardingTutorialStateMachine.onPillTap(state)

        state = OnboardingTutorialStateMachine.onFakeRecordingCompleted(state)
        assertEquals(OnboardingSpeechCue.COMPOSE_REQUEST, state.speechCue)
        assertTrue(state.nextEnabled)

        state = OnboardingTutorialStateMachine.onNext(state)
        assertEquals(OnboardingTutorialStep.FAKE_PROCESSING_COMPOSE, state.step)

        state = OnboardingTutorialStateMachine.onFakeProcessingCompleted(state)
        assertTrue(state.nextEnabled)
        assertEquals(OnboardingOutputVariant.INITIAL_LIST, state.outputVariant)

        state = OnboardingTutorialStateMachine.onNext(state)
        assertEquals(OnboardingTutorialStep.WAIT_FOR_EDIT_TAP, state.step)
        assertTrue(state.showEditButton)
    }

    @Test
    fun editFlowReplacesEggsWithMilkInFinalOutputVariant() {
        var state = OnboardingTutorialStateMachine.initialState()
        state = OnboardingTutorialStateMachine.onPillTap(state)
        state = OnboardingTutorialStateMachine.onFakeRecordingCompleted(state)
        state = OnboardingTutorialStateMachine.onNext(state)
        state = OnboardingTutorialStateMachine.onFakeProcessingCompleted(state)
        state = OnboardingTutorialStateMachine.onNext(state)

        state = OnboardingTutorialStateMachine.onEditTap(state)
        assertEquals(OnboardingTutorialStep.FAKE_RECORDING_EDIT, state.step)

        state = OnboardingTutorialStateMachine.onFakeRecordingCompleted(state)
        assertEquals(OnboardingSpeechCue.EDIT_REQUEST, state.speechCue)
        assertTrue(state.nextEnabled)

        state = OnboardingTutorialStateMachine.onNext(state)
        state = OnboardingTutorialStateMachine.onFakeProcessingCompleted(state)
        assertEquals(OnboardingOutputVariant.FINAL_LIST, state.outputVariant)
        assertTrue(state.nextEnabled)

        state = OnboardingTutorialStateMachine.onNext(state)
        assertEquals(OnboardingTutorialStep.FINAL_REVIEW, state.step)
    }

    @Test
    fun doneIsAllowedOnlyOnFinalStep() {
        var state = OnboardingTutorialStateMachine.initialState()
        assertFalse(OnboardingTutorialStateMachine.onDone(state))

        state = state.copy(step = OnboardingTutorialStep.FINAL_REVIEW)
        assertTrue(OnboardingTutorialStateMachine.onDone(state))
    }
}
