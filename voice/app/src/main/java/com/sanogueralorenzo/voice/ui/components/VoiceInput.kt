package com.sanogueralorenzo.voice.ui.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.sanogueralorenzo.voice.R

@Composable
fun VoiceInput(
    value: String,
    onValueChange: (String) -> Unit,
    voiceImeSelected: Boolean,
    onRequestKeyboardPicker: () -> Unit,
    autoFocusOnResume: Boolean = false
) {
    var showKeyboardDialog by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }
    val keyboardController = LocalSoftwareKeyboardController.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val latestFocusAction by rememberUpdatedState(
        newValue = {
            if (!voiceImeSelected) return@rememberUpdatedState
            focusRequester.requestFocus()
            keyboardController?.show()
        }
    )

    DisposableEffect(lifecycleOwner, autoFocusOnResume, voiceImeSelected) {
        val observer = LifecycleEventObserver { _, event ->
            if (
                event == Lifecycle.Event.ON_RESUME &&
                autoFocusOnResume &&
                voiceImeSelected
            ) {
                latestFocusAction()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    RoundedInputBar(
        value = value,
        onValueChange = onValueChange,
        focusRequester = focusRequester,
        enabled = voiceImeSelected,
        onBlockedTap = { showKeyboardDialog = true }
    )

    if (showKeyboardDialog) {
        AlertDialog(
            onDismissRequest = { showKeyboardDialog = false },
            title = { Text(text = stringResource(R.string.setup_input_keyboard_required_title)) },
            text = { Text(text = stringResource(R.string.setup_input_keyboard_required_body)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showKeyboardDialog = false
                        onRequestKeyboardPicker()
                    }
                ) {
                    Text(text = stringResource(R.string.setup_choose_keyboard))
                }
            },
            dismissButton = {
                TextButton(onClick = { showKeyboardDialog = false }) {
                    Text(text = stringResource(android.R.string.cancel))
                }
            }
        )
    }
}
