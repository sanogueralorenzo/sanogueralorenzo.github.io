package com.sanogueralorenzo.voice.setup

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowForward
import androidx.compose.material3.Button
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.sanogueralorenzo.voice.R
import kotlinx.coroutines.delay

@Composable
fun OnboardingTutorialScreen(
    onDone: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val focusRequester = remember { FocusRequester() }
    val viewModel = remember {
        OnboardingTutorialViewModel(OnboardingTutorialUiState())
    }
    val uiState by viewModel.collectAsStateWithLifecycle()
    val tutorialState = uiState.tutorialState

    val isSentPreview = tutorialState.step == OnboardingTutorialStep.SENT_PREVIEW

    LaunchedEffect(tutorialState.step) {
        if (isSentPreview) {
            keyboardController?.hide()
            return@LaunchedEffect
        }
        delay(120L)
        focusRequester.requestFocus()
        keyboardController?.show()
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        bottomBar = {
            if (!isSentPreview) {
                OnboardingInputBar(
                    inputText = tutorialState.inputText,
                    onInputChange = { value -> viewModel.onInputChanged(value) },
                    focusRequester = focusRequester
                )
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 20.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = stringResource(instructionResId(tutorialState.step)),
                style = MaterialTheme.typography.titleLarge
            )

            Spacer(modifier = Modifier.height(22.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedButton(
                    onClick = { showImePicker(context) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(text = stringResource(R.string.onboarding_tutorial_open_picker))
                }
                OutlinedButton(
                    onClick = { openImeSettings(context) },
                    modifier = Modifier.weight(1f)
                ) {
                    Text(text = stringResource(R.string.onboarding_tutorial_open_settings))
                }
            }

            AnimatedVisibility(
                visible = isSentPreview,
                enter = fadeIn(animationSpec = tween(durationMillis = 220)) +
                    expandVertically(animationSpec = tween(durationMillis = 220))
            ) {
                SentPreviewBubble(
                    text = tutorialState.sentMessage,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (isSentPreview) {
                    Button(
                        onClick = {
                            if (viewModel.canFinish()) onDone()
                        },
                        enabled = viewModel.canFinish()
                    ) {
                        Text(text = stringResource(R.string.onboarding_tutorial_done))
                    }
                } else {
                    FilledIconButton(
                        onClick = { viewModel.onNext() },
                        enabled = viewModel.canAdvance()
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

@Composable
private fun OnboardingInputBar(
    inputText: String,
    onInputChange: (String) -> Unit,
    focusRequester: FocusRequester
) {
    TextField(
        value = inputText,
        onValueChange = onInputChange,
        modifier = Modifier
            .fillMaxWidth()
            .imePadding()
            .navigationBarsPadding()
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .focusRequester(focusRequester),
        placeholder = {
            Text(text = stringResource(R.string.onboarding_tutorial_input_placeholder))
        },
        shape = RoundedCornerShape(24.dp),
        minLines = 1,
        maxLines = 5,
        colors = TextFieldDefaults.colors(
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
            focusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
            unfocusedContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
            disabledContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest
        )
    )
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

private fun instructionResId(step: OnboardingTutorialStep): Int {
    return when (step) {
        OnboardingTutorialStep.WRITE_WITH_VOICE -> R.string.onboarding_tutorial_real_instruction_compose
        OnboardingTutorialStep.EDIT_WITH_VOICE -> R.string.onboarding_tutorial_real_instruction_edit
        OnboardingTutorialStep.SENT_PREVIEW -> R.string.onboarding_tutorial_real_instruction_sent
    }
}

private fun openImeSettings(context: Context) {
    val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
}

private fun showImePicker(context: Context) {
    val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
    imm.showInputMethodPicker()
}
