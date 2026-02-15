package com.sanogueralorenzo.voice.setup

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ime.VoiceKeyboardImeContent
import com.sanogueralorenzo.voice.ime.VoiceProcessingStage
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
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
    var showSentPreview by remember { mutableStateOf(false) }
    val showNextControl = tutorialState.step != OnboardingTutorialStep.WAIT_FOR_PILL_TAP &&
        tutorialState.step != OnboardingTutorialStep.WAIT_FOR_EDIT_TAP &&
        tutorialState.step != OnboardingTutorialStep.WAIT_FOR_SEND_TAP
    val showInstructionTitle = tutorialState.step != OnboardingTutorialStep.FINAL_REVIEW

    val actionPrompt = when (tutorialState.step) {
        OnboardingTutorialStep.WAIT_FOR_PILL_TAP -> KeyboardActionPrompt(
            text = stringResource(R.string.onboarding_tutorial_action_pill),
            target = KeyboardActionTarget.CENTER_PILL
        )

        OnboardingTutorialStep.WAIT_FOR_EDIT_TAP -> KeyboardActionPrompt(
            text = stringResource(R.string.onboarding_tutorial_action_edit),
            target = KeyboardActionTarget.LEFT_EDIT
        )

        OnboardingTutorialStep.WAIT_FOR_SEND_TAP -> KeyboardActionPrompt(
            text = stringResource(R.string.onboarding_tutorial_action_send),
            target = KeyboardActionTarget.RIGHT_SEND
        )

        else -> null
    }

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

    LaunchedEffect(tutorialState.step) {
        if (tutorialState.step != OnboardingTutorialStep.FINAL_REVIEW) {
            showSentPreview = false
        }
    }

    LaunchedEffect(showSentPreview) {
        if (showSentPreview) {
            delay(1000L)
            onDone()
        }
    }

    LaunchedEffect(speechText) {
        showSpeechCard = false
        if (!speechText.isNullOrBlank()) {
            delay(220L)
            showSpeechCard = true
        }
    }

    LaunchedEffect(outputText) {
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
                onSendTap = { viewModel.onSendTap() },
                onDebugToggle = {},
                onDebugLongPress = {},
                showDebugButton = false
            )
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (showInstructionTitle) {
                    Text(
                        text = stringResource(instructionResId(tutorialState.step)),
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(bottom = 4.dp)
                    )
                }

                AnimatedVisibility(
                    visible = !showSentPreview && showSpeechCard && speechText != null,
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
                    visible = !showSentPreview && showOutputCard && outputText != null,
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

                AnimatedVisibility(
                    visible = showSentPreview && isFinalStep,
                    enter = fadeIn(animationSpec = tween(durationMillis = 220)) +
                        expandVertically(animationSpec = tween(durationMillis = 220))
                ) {
                    SentPreviewBubble(
                        text = outputText.orEmpty(),
                        modifier = Modifier.fillMaxWidth()
                    )
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
                                        showSentPreview = true
                                    }
                                },
                                enabled = nextEnabled && !showSentPreview
                            ) {
                                Text(
                                    text = if (showSentPreview) {
                                        stringResource(R.string.onboarding_tutorial_sending)
                                    } else {
                                        stringResource(R.string.onboarding_tutorial_done)
                                    }
                                )
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

            AnimatedVisibility(
                visible = actionPrompt != null,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(horizontal = 18.dp, vertical = 4.dp),
                enter = fadeIn(animationSpec = tween(durationMillis = 220))
            ) {
                if (actionPrompt != null) {
                    KeyboardActionOverlay(prompt = actionPrompt)
                }
            }
        }
    }
}

data class KeyboardActionPrompt(
    val text: String,
    val target: KeyboardActionTarget
)

enum class KeyboardActionTarget {
    CENTER_PILL,
    LEFT_EDIT,
    RIGHT_SEND
}

@Composable
private fun KeyboardActionOverlay(prompt: KeyboardActionPrompt) {
    val bubbleAlignment = when (prompt.target) {
        KeyboardActionTarget.CENTER_PILL -> Alignment.BottomCenter
        KeyboardActionTarget.LEFT_EDIT -> Alignment.BottomStart
        KeyboardActionTarget.RIGHT_SEND -> Alignment.BottomEnd
    }
    val bubbleOffsetX = when (prompt.target) {
        KeyboardActionTarget.CENTER_PILL -> 0.dp
        KeyboardActionTarget.LEFT_EDIT -> 10.dp
        KeyboardActionTarget.RIGHT_SEND -> (-10).dp
    }

    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = bubbleAlignment
    ) {
        Column(
            modifier = Modifier
                .offset(x = bubbleOffsetX)
                .widthIn(max = 260.dp),
            horizontalAlignment = when (prompt.target) {
                KeyboardActionTarget.CENTER_PILL -> Alignment.CenterHorizontally
                KeyboardActionTarget.LEFT_EDIT -> Alignment.Start
                KeyboardActionTarget.RIGHT_SEND -> Alignment.End
            }
        ) {
            Surface(
                shape = RoundedCornerShape(999.dp),
                color = Color(0xFF161616),
                modifier = Modifier.border(
                    width = 1.dp,
                    color = Color.White.copy(alpha = 0.45f),
                    shape = RoundedCornerShape(999.dp)
                )
            ) {
                Text(
                    text = prompt.text,
                    color = Color.White,
                    fontSize = 12.sp,
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp)
                )
            }
            CleanPointerArrow(
                target = prompt.target,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(76.dp)
                    .padding(horizontal = 4.dp)
            )
        }
    }
}

@Composable
private fun CleanPointerArrow(
    target: KeyboardActionTarget,
    modifier: Modifier = Modifier
) {
    Canvas(modifier = modifier) {
        val startX = size.width * 0.5f
        val startY = 8f
        val endX = when (target) {
            KeyboardActionTarget.CENTER_PILL -> size.width * 0.5f
            KeyboardActionTarget.LEFT_EDIT -> size.width * 0.08f
            KeyboardActionTarget.RIGHT_SEND -> size.width * 0.92f
        }
        val endY = size.height * 0.9f

        drawLine(
            color = Color.White,
            start = Offset(startX, startY),
            end = Offset(endX, endY),
            strokeWidth = 3.6f
        )

        val angle = atan2((endY - startY), (endX - startX))
        val headLength = 14f
        val spread = 0.56f
        val left = Offset(
            x = endX - (headLength * cos(angle - spread)).toFloat(),
            y = endY - (headLength * sin(angle - spread)).toFloat()
        )
        val right = Offset(
            x = endX - (headLength * cos(angle + spread)).toFloat(),
            y = endY - (headLength * sin(angle + spread)).toFloat()
        )

        drawLine(
            color = Color.White,
            start = Offset(endX, endY),
            end = left,
            strokeWidth = 4.2f
        )
        drawLine(
            color = Color.White,
            start = Offset(endX, endY),
            end = right,
            strokeWidth = 4.2f
        )
    }
}

@Composable
private fun SentPreviewBubble(
    text: String,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.End
    ) {
        Surface(
            color = Color(0xFFDCF8C6),
            shape = RoundedCornerShape(
                topStart = 18.dp,
                topEnd = 6.dp,
                bottomStart = 18.dp,
                bottomEnd = 18.dp
            ),
            modifier = Modifier.widthIn(max = 320.dp)
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = text,
                    color = Color(0xFF111B21),
                    style = MaterialTheme.typography.bodyMedium
                )
                Text(
                    text = stringResource(R.string.onboarding_tutorial_sent_now),
                    color = Color(0xFF4D5E66),
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.align(Alignment.End)
                )
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
        OnboardingTutorialStep.WAIT_FOR_SEND_TAP -> R.string.onboarding_tutorial_instruction_tap_send
        OnboardingTutorialStep.FINAL_REVIEW -> R.string.onboarding_tutorial_instruction_final
    }
}
