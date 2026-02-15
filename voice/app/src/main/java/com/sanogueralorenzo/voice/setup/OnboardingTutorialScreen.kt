package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ime.VoiceKeyboardImeContent
import com.sanogueralorenzo.voice.ime.VoiceProcessingStage
import kotlinx.coroutines.delay

@Composable
fun OnboardingTutorialScreen(
    onDone: () -> Unit,
    modifier: Modifier = Modifier
) {
    var tutorialState by remember {
        mutableStateOf(OnboardingTutorialStateMachine.initialState())
    }

    LaunchedEffect(tutorialState.step) {
        val startedStep = tutorialState.step
        when (startedStep) {
            OnboardingTutorialStep.FAKE_RECORDING_COMPOSE,
            OnboardingTutorialStep.FAKE_RECORDING_EDIT -> {
                val levels = floatArrayOf(0.12f, 0.4f, 0.72f, 0.35f, 0.61f, 0.28f, 0.66f, 0.32f)
                for (level in levels) {
                    if (tutorialState.step != startedStep) return@LaunchedEffect
                    tutorialState = tutorialState.copy(audioLevel = level)
                    delay(130L)
                }
                if (tutorialState.step == startedStep) {
                    tutorialState = OnboardingTutorialStateMachine.onFakeRecordingCompleted(tutorialState)
                }
            }

            OnboardingTutorialStep.FAKE_PROCESSING_COMPOSE,
            OnboardingTutorialStep.FAKE_PROCESSING_EDIT -> {
                tutorialState = tutorialState.copy(keyboardStage = VoiceProcessingStage.TRANSCRIBING)
                delay(700L)
                if (tutorialState.step != startedStep) return@LaunchedEffect
                tutorialState = tutorialState.copy(keyboardStage = VoiceProcessingStage.REWRITING)
                delay(700L)
                if (tutorialState.step == startedStep) {
                    tutorialState = OnboardingTutorialStateMachine.onFakeProcessingCompleted(tutorialState)
                }
            }

            else -> Unit
        }
    }

    val keyboardState = OnboardingTutorialStateMachine.toKeyboardState(tutorialState)
    val stepNumber = OnboardingTutorialStateMachine.currentStepNumber(tutorialState.step)
    val isFinalStep = tutorialState.step == OnboardingTutorialStep.FINAL_REVIEW
    val nextEnabled = if (isFinalStep) true else tutorialState.nextEnabled

    val speechText = when (tutorialState.speechCue) {
        OnboardingSpeechCue.NONE -> null
        OnboardingSpeechCue.COMPOSE_REQUEST -> stringResource(R.string.onboarding_tutorial_speech_compose)
        OnboardingSpeechCue.EDIT_REQUEST -> stringResource(R.string.onboarding_tutorial_speech_edit)
    }
    val outputText = when (tutorialState.outputVariant) {
        OnboardingOutputVariant.NONE -> null
        OnboardingOutputVariant.INITIAL_LIST -> stringResource(R.string.onboarding_tutorial_output_initial)
        OnboardingOutputVariant.FINAL_LIST -> stringResource(R.string.onboarding_tutorial_output_final)
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        bottomBar = {
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 12.dp)
                ) {
                    Button(
                        onClick = {
                            if (isFinalStep) {
                                if (OnboardingTutorialStateMachine.onDone(tutorialState)) {
                                    onDone()
                                }
                            } else {
                                tutorialState = OnboardingTutorialStateMachine.onNext(tutorialState)
                            }
                        },
                        enabled = nextEnabled,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(
                            text = if (isFinalStep) {
                                stringResource(R.string.onboarding_tutorial_done)
                            } else {
                                stringResource(R.string.onboarding_tutorial_next)
                            }
                        )
                    }
                }
                VoiceKeyboardImeContent(
                    state = keyboardState,
                    onIdleTap = {
                        tutorialState = OnboardingTutorialStateMachine.onPillTap(tutorialState)
                    },
                    onEditTap = {
                        tutorialState = OnboardingTutorialStateMachine.onEditTap(tutorialState)
                    },
                    onDeleteTap = {},
                    onSendTap = {},
                    onDebugToggle = {},
                    onDebugLongPress = {},
                    showDebugButton = false
                )
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Text(
                        text = stringResource(R.string.onboarding_section_title),
                        style = MaterialTheme.typography.titleLarge
                    )
                    Text(
                        text = stringResource(
                            R.string.onboarding_tutorial_step_counter,
                            stepNumber,
                            OnboardingTutorialStateMachine.TOTAL_STEPS
                        ),
                        style = MaterialTheme.typography.bodySmall
                    )
                    Text(
                        text = stringResource(R.string.onboarding_tutorial_badge),
                        style = MaterialTheme.typography.labelMedium
                    )
                    Text(
                        text = stringResource(instructionResId(tutorialState.step)),
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Text(
                        text = stringResource(helperResId(tutorialState.step, tutorialState.nextEnabled)),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }

            if (speechText != null) {
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.onboarding_tutorial_speech_label),
                            style = MaterialTheme.typography.titleSmall
                        )
                        Text(
                            text = speechText,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }

            if (outputText != null) {
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = stringResource(R.string.onboarding_tutorial_output_label),
                            style = MaterialTheme.typography.titleSmall
                        )
                        Text(
                            text = outputText,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }
        }
    }
}

private fun instructionResId(step: OnboardingTutorialStep): Int {
    return when (step) {
        OnboardingTutorialStep.INTRO -> R.string.onboarding_tutorial_instruction_intro
        OnboardingTutorialStep.WAIT_FOR_PILL_TAP -> R.string.onboarding_tutorial_instruction_tap_pill
        OnboardingTutorialStep.FAKE_RECORDING_COMPOSE -> R.string.onboarding_tutorial_instruction_recording_compose
        OnboardingTutorialStep.FAKE_PROCESSING_COMPOSE -> R.string.onboarding_tutorial_instruction_processing_compose
        OnboardingTutorialStep.WAIT_FOR_EDIT_TAP -> R.string.onboarding_tutorial_instruction_tap_edit
        OnboardingTutorialStep.FAKE_RECORDING_EDIT -> R.string.onboarding_tutorial_instruction_recording_edit
        OnboardingTutorialStep.FAKE_PROCESSING_EDIT -> R.string.onboarding_tutorial_instruction_processing_edit
        OnboardingTutorialStep.FINAL_REVIEW -> R.string.onboarding_tutorial_instruction_final
    }
}

private fun helperResId(step: OnboardingTutorialStep, nextEnabled: Boolean): Int {
    return when (step) {
        OnboardingTutorialStep.INTRO -> R.string.onboarding_tutorial_hint_tap_next
        OnboardingTutorialStep.WAIT_FOR_PILL_TAP -> {
            if (nextEnabled) {
                R.string.onboarding_tutorial_hint_tap_next
            } else {
                R.string.onboarding_tutorial_hint_tap_pill
            }
        }

        OnboardingTutorialStep.FAKE_RECORDING_COMPOSE,
        OnboardingTutorialStep.FAKE_RECORDING_EDIT -> {
            if (nextEnabled) {
                R.string.onboarding_tutorial_hint_tap_next
            } else {
                R.string.onboarding_tutorial_hint_recording
            }
        }

        OnboardingTutorialStep.FAKE_PROCESSING_COMPOSE -> {
            if (nextEnabled) {
                R.string.onboarding_tutorial_hint_tap_next
            } else {
                R.string.onboarding_tutorial_hint_processing_compose
            }
        }

        OnboardingTutorialStep.WAIT_FOR_EDIT_TAP -> {
            if (nextEnabled) {
                R.string.onboarding_tutorial_hint_tap_next
            } else {
                R.string.onboarding_tutorial_hint_tap_edit
            }
        }

        OnboardingTutorialStep.FAKE_PROCESSING_EDIT -> {
            if (nextEnabled) {
                R.string.onboarding_tutorial_hint_tap_next
            } else {
                R.string.onboarding_tutorial_hint_processing_edit
            }
        }

        OnboardingTutorialStep.FINAL_REVIEW -> R.string.onboarding_tutorial_hint_done
    }
}
