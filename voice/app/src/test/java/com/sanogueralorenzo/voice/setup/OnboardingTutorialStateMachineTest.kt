package com.sanogueralorenzo.voice.setup

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OnboardingTutorialStateMachineTest {
    @Test
    fun composeStepRequiresNonBlankInputToAdvance() {
        var state = OnboardingTutorialStateMachine.initialState()

        assertEquals(OnboardingTutorialStep.WRITE_WITH_VOICE, state.step)
        assertFalse(OnboardingTutorialStateMachine.canAdvance(state))

        state = OnboardingTutorialStateMachine.onNext(state)
        assertEquals(OnboardingTutorialStep.WRITE_WITH_VOICE, state.step)

        state = OnboardingTutorialStateMachine.onInputChanged(state, "Hey Mia buy apples eggs")
        assertTrue(OnboardingTutorialStateMachine.canAdvance(state))

        state = OnboardingTutorialStateMachine.onNext(state)
        assertEquals(OnboardingTutorialStep.EDIT_WITH_VOICE, state.step)
        assertEquals("Hey Mia buy apples eggs", state.composeSnapshot)
    }

    @Test
    fun editStepRequiresChangedTextAndThenTransitionsToSentPreview() {
        var state = OnboardingTutorialStateMachine.initialState()
        state = OnboardingTutorialStateMachine.onInputChanged(state, "Initial draft")
        state = OnboardingTutorialStateMachine.onNext(state)

        assertEquals(OnboardingTutorialStep.EDIT_WITH_VOICE, state.step)
        assertFalse(OnboardingTutorialStateMachine.canAdvance(state))

        state = OnboardingTutorialStateMachine.onInputChanged(state, "Initial draft with milk")
        assertTrue(OnboardingTutorialStateMachine.canAdvance(state))

        state = OnboardingTutorialStateMachine.onNext(state)
        assertEquals(OnboardingTutorialStep.SENT_PREVIEW, state.step)
        assertEquals("Initial draft with milk", state.sentMessage)
    }

    @Test
    fun doneAllowedOnlyOnSentPreview() {
        var state = OnboardingTutorialStateMachine.initialState()
        assertFalse(OnboardingTutorialStateMachine.onDone(state))

        state = state.copy(step = OnboardingTutorialStep.SENT_PREVIEW)
        assertTrue(OnboardingTutorialStateMachine.onDone(state))
    }
}
