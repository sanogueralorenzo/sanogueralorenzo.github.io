package com.sanogueralorenzo.voice.setup

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ime.VoiceKeyboardImeContent
import com.sanogueralorenzo.voice.ime.VoiceProcessingStage
import kotlinx.coroutines.delay

@Composable
fun OnboardingTutorialScreen(
    onDone: () -> Unit,
    modifier: Modifier = Modifier
) {
    val viewModel = remember {
        OnboardingTutorialViewModel(OnboardingTutorialUiState())
    }
    val uiState by viewModel.collectAsStateWithLifecycle()
    val tutorialState = uiState.tutorialState

    LaunchedEffect(tutorialState.step) {
        val startedStep = tutorialState.step
        when (startedStep) {
            OnboardingTutorialStep.FAKE_RECORDING_COMPOSE,
            OnboardingTutorialStep.FAKE_RECORDING_EDIT -> {
                val levels = floatArrayOf(0.12f, 0.4f, 0.72f, 0.35f, 0.61f, 0.28f, 0.66f, 0.32f)
                for (level in levels) {
                    if (viewModel.currentStep() != startedStep) return@LaunchedEffect
                    viewModel.setAudioLevel(level)
                    delay(130L)
                }
                if (viewModel.currentStep() == startedStep) {
                    viewModel.onFakeRecordingCompleted()
                }
            }

            OnboardingTutorialStep.FAKE_PROCESSING_COMPOSE,
            OnboardingTutorialStep.FAKE_PROCESSING_EDIT -> {
                viewModel.setProcessingStage(VoiceProcessingStage.TRANSCRIBING)
                delay(700L)
                if (viewModel.currentStep() != startedStep) return@LaunchedEffect
                viewModel.setProcessingStage(VoiceProcessingStage.REWRITING)
                delay(700L)
                if (viewModel.currentStep() == startedStep) {
                    viewModel.onFakeProcessingCompleted()
                }
            }

            else -> Unit
        }
    }

    val keyboardState = OnboardingTutorialStateMachine.toKeyboardState(tutorialState)
    val isFinalStep = tutorialState.step == OnboardingTutorialStep.FINAL_REVIEW
    val nextEnabled = if (isFinalStep) true else tutorialState.nextEnabled
    val showNextControl = tutorialState.step != OnboardingTutorialStep.WAIT_FOR_PILL_TAP &&
        tutorialState.step != OnboardingTutorialStep.WAIT_FOR_EDIT_TAP

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

    var showSpeechCard by remember { mutableStateOf(false) }
    var showOutputCard by remember { mutableStateOf(false) }

    LaunchedEffect(speechText, tutorialState.step) {
        showSpeechCard = false
        if (!speechText.isNullOrBlank()) {
            delay(220L)
            showSpeechCard = true
        }
    }

    LaunchedEffect(outputText, tutorialState.step) {
        showOutputCard = false
        if (!outputText.isNullOrBlank()) {
            delay(300L)
            showOutputCard = true
        }
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        bottomBar = {
            VoiceKeyboardImeContent(
                state = keyboardState,
                onIdleTap = { viewModel.onPillTap() },
                onEditTap = { viewModel.onEditTap() },
                onDeleteTap = {},
                onSendTap = {},
                onDebugToggle = {},
                onDebugLongPress = {},
                showDebugButton = false
            )
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
                        text = stringResource(instructionResId(tutorialState.step)),
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Text(
                        text = stringResource(helperResId(tutorialState.step, tutorialState.nextEnabled)),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }

            AnimatedVisibility(
                visible = showSpeechCard && speechText != null,
                enter = fadeIn(animationSpec = tween(durationMillis = 220)) +
                    expandVertically(animationSpec = tween(durationMillis = 220))
            ) {
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
                        AnimatedTypewriterText(
                            text = speechText.orEmpty(),
                            style = MaterialTheme.typography.bodyMedium,
                            startDelayMs = 100L,
                            charDelayMs = 12L
                        )
                    }
                }
            }

            AnimatedVisibility(
                visible = showOutputCard && outputText != null,
                enter = fadeIn(animationSpec = tween(durationMillis = 260)) +
                    expandVertically(animationSpec = tween(durationMillis = 260))
            ) {
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
                        AnimatedTypewriterText(
                            text = outputText.orEmpty(),
                            style = MaterialTheme.typography.bodyMedium,
                            startDelayMs = 120L,
                            charDelayMs = 8L
                        )
                    }
                }
            }

            if (showNextControl) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End
                ) {
                    if (isFinalStep) {
                        Button(
                            onClick = {
                                if (viewModel.canFinish()) {
                                    onDone()
                                }
                            },
                            enabled = nextEnabled
                        ) {
                            Text(text = stringResource(R.string.onboarding_tutorial_done))
                        }
                    } else {
                        FilledIconButton(
                            onClick = { viewModel.onNext() },
                            enabled = nextEnabled
                        ) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Rounded.ArrowForward,
                                contentDescription = stringResource(R.string.onboarding_tutorial_next)
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun AnimatedTypewriterText(
    text: String,
    style: TextStyle,
    startDelayMs: Long,
    charDelayMs: Long
) {
    var visibleChars by remember(text) { mutableStateOf(0) }

    LaunchedEffect(text) {
        visibleChars = 0
        if (text.isBlank()) return@LaunchedEffect
        delay(startDelayMs)
        while (visibleChars < text.length) {
            visibleChars += 1
            delay(charDelayMs)
        }
    }

    Text(
        text = text.take(visibleChars),
        style = style
    )
}

private fun instructionResId(step: OnboardingTutorialStep): Int {
    return when (step) {
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
        OnboardingTutorialStep.WAIT_FOR_PILL_TAP -> R.string.onboarding_tutorial_hint_tap_pill

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

        OnboardingTutorialStep.WAIT_FOR_EDIT_TAP -> R.string.onboarding_tutorial_hint_tap_edit

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
