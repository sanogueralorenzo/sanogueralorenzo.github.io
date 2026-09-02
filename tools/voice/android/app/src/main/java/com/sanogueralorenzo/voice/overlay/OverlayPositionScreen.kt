package com.sanogueralorenzo.voice.overlay

import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.KeyboardArrowUp
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.keyboard.VoiceKeyboardStatusReader
import com.sanogueralorenzo.voice.ui.OnLifecycle
import kotlinx.coroutines.delay

@Composable
fun OverlayPositionScreen(
    onKeyboardSelectionRequiredChanged: (Boolean) -> Unit = {}
) {
    val viewModel = mavericksViewModel<OverlayPositionViewModel, OverlayPositionState>()
    val state by viewModel.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var numberInput by rememberSaveable { mutableStateOf("") }
    var voiceKeyboardSelected by remember {
        mutableStateOf(VoiceKeyboardStatusReader.read(context).selected)
    }
    val inputFocusRequester = remember { FocusRequester() }
    val keyboardController = LocalSoftwareKeyboardController.current
    val inputMethodManager = remember(context) {
        context.getSystemService(InputMethodManager::class.java)
    }
    val hostView = LocalView.current
    val positionPreview = remember(hostView) {
        OverlayPositionPreview(
            hostView = hostView,
            onPositionChanged = viewModel::setBubblePosition,
            onDefaultPositionChanged = viewModel::setDefaultBubblePosition
        )
    }

    DisposableEffect(positionPreview) {
        OverlayAccessibilityService.setPositioningActive(true)
        onDispose {
            positionPreview.dismiss()
            OverlayAccessibilityService.setPositioningActive(false)
        }
    }

    DisposableEffect(context) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                voiceKeyboardSelected = VoiceKeyboardStatusReader.read(context).selected
            }
        }
        context.contentResolver.registerContentObserver(
            Settings.Secure.getUriFor(Settings.Secure.DEFAULT_INPUT_METHOD),
            false,
            observer
        )
        onDispose { context.contentResolver.unregisterContentObserver(observer) }
    }

    LaunchedEffect(
        positionPreview,
        state.positionLoaded,
        state.bubbleX,
        state.bubbleY,
        state.bubbleSizeDp,
        state.hasCustomBubblePosition,
        voiceKeyboardSelected
    ) {
        if (state.positionLoaded && !voiceKeyboardSelected) {
            positionPreview.show(
                x = state.bubbleX,
                y = state.bubbleY,
                sizeDp = state.bubbleSizeDp,
                hasCustomPosition = state.hasCustomBubblePosition
            )
        } else {
            positionPreview.dismiss()
        }
    }

    LaunchedEffect(voiceKeyboardSelected) {
        onKeyboardSelectionRequiredChanged(voiceKeyboardSelected)
        if (voiceKeyboardSelected) {
            keyboardController?.hide()
            inputMethodManager?.showInputMethodPicker()
        } else {
            delay(KEYBOARD_SHOW_DELAY_MS)
            inputFocusRequester.requestFocus()
            keyboardController?.show()
        }
    }

    OnLifecycle(Lifecycle.Event.ON_START, Lifecycle.Event.ON_RESUME) {
        viewModel.refreshStatus()
        OverlayAccessibilityService.setPositioningActive(true)
        val selected = VoiceKeyboardStatusReader.read(context).selected
        voiceKeyboardSelected = selected
        if (state.positionLoaded && !selected) {
            positionPreview.show(
                x = state.bubbleX,
                y = state.bubbleY,
                sizeDp = state.bubbleSizeDp,
                hasCustomPosition = state.hasCustomBubblePosition
            )
        }
    }
    OnLifecycle(Lifecycle.Event.ON_PAUSE, Lifecycle.Event.ON_STOP) {
        positionPreview.dismiss()
        OverlayAccessibilityService.setPositioningActive(false)
    }

    if (voiceKeyboardSelected) {
        KeyboardSelectionPrompt(
            onChooseKeyboard = { inputMethodManager?.showInputMethodPicker() }
        )
    } else {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .imePadding()
                .padding(horizontal = 20.dp)
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(top = 12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                PositionInstructions()
                if (state.positionLoaded) {
                    PositionControls(
                        bubbleSizeDp = state.bubbleSizeDp,
                        onDecreaseSize = { viewModel.adjustBubbleSizeDp(-1) },
                        onIncreaseSize = { viewModel.adjustBubbleSizeDp(1) },
                        onNudge = viewModel::nudgeBubblePosition
                    )
                }

                if (!state.accessibilityServiceEnabled) {
                    Text(
                        text = stringResource(R.string.overlay_position_enable_accessibility_note),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }

            TextField(
                value = numberInput,
                onValueChange = { value -> numberInput = value },
                placeholder = {
                    Text(text = stringResource(R.string.overlay_position_message_placeholder))
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .focusRequester(inputFocusRequester)
                    .padding(top = 12.dp, bottom = 16.dp),
                singleLine = true
            )
        }
    }
}

@Composable
private fun KeyboardSelectionPrompt(onChooseKeyboard: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 24.dp)
            .padding(top = 64.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Top
    ) {
        Text(
            text = stringResource(R.string.overlay_position_choose_keyboard_title),
            style = MaterialTheme.typography.titleMedium
        )
        Text(
            text = stringResource(R.string.overlay_position_choose_keyboard_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 8.dp)
        )
        Button(
            onClick = onChooseKeyboard,
            modifier = Modifier.padding(top = 16.dp)
        ) {
            Text(text = stringResource(R.string.overlay_position_choose_keyboard_action))
        }
    }
}

@Composable
private fun PositionInstructions() {
    Column(
        modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(
            text = stringResource(R.string.overlay_position_instructions_body),
            style = MaterialTheme.typography.titleMedium
        )
        Text(
            text = stringResource(R.string.overlay_position_mic_indicator_note),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun PositionControls(
    bubbleSizeDp: Int,
    onDecreaseSize: () -> Unit,
    onIncreaseSize: () -> Unit,
    onNudge: (deltaXDp: Int, deltaYDp: Int) -> Unit
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.overlay_position_size_label, bubbleSizeDp),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f)
                )
                ControlButton(
                    icon = Icons.Rounded.Remove,
                    contentDescription = stringResource(R.string.overlay_position_size_decrease),
                    onClick = onDecreaseSize
                )
                ControlButton(
                    icon = Icons.Rounded.Add,
                    contentDescription = stringResource(R.string.overlay_position_size_increase),
                    onClick = onIncreaseSize
                )
            }

            HorizontalDivider()

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = stringResource(R.string.overlay_position_nudge_label),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f)
                )
                ControlButton(
                    icon = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                    contentDescription = stringResource(R.string.overlay_position_nudge_left),
                    onClick = { onNudge(-1, 0) }
                )
                ControlButton(
                    icon = Icons.Rounded.KeyboardArrowUp,
                    contentDescription = stringResource(R.string.overlay_position_nudge_up),
                    onClick = { onNudge(0, -1) }
                )
                ControlButton(
                    icon = Icons.Rounded.KeyboardArrowDown,
                    contentDescription = stringResource(R.string.overlay_position_nudge_down),
                    onClick = { onNudge(0, 1) }
                )
                ControlButton(
                    icon = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    contentDescription = stringResource(R.string.overlay_position_nudge_right),
                    onClick = { onNudge(1, 0) }
                )
            }
        }
    }
}

@Composable
private fun ControlButton(
    icon: ImageVector,
    contentDescription: String,
    onClick: () -> Unit
) {
    FilledTonalIconButton(
        modifier = Modifier.size(CONTROL_BUTTON_SIZE),
        onClick = onClick
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription
        )
    }
}

private val CONTROL_BUTTON_SIZE = 40.dp
private const val KEYBOARD_SHOW_DELAY_MS = 200L
