package com.sanogueralorenzo.voice.ui.components

import androidx.lifecycle.Lifecycle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.ui.OnLifecycle

@Composable
fun VoiceInput(
    value: String,
    onValueChange: (String) -> Unit,
    voiceImeSelected: Boolean,
    onRequestKeyboardPicker: () -> Unit,
    autoFocusOnResume: Boolean = false,
    enforceVoiceIme: Boolean = true
) {
    var showKeyboardDialog by remember { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }
    val keyboardController = LocalSoftwareKeyboardController.current
    val isInputEnabled = voiceImeSelected || !enforceVoiceIme
    val latestFocusAction by rememberUpdatedState(
        newValue = {
            if (!isInputEnabled) return@rememberUpdatedState
            focusRequester.requestFocus()
            keyboardController?.show()
        }
    )

    OnLifecycle(Lifecycle.Event.ON_RESUME) {
        if (autoFocusOnResume && isInputEnabled) {
            latestFocusAction()
        }
    }

    RoundedInputBar(
        value = value,
        onValueChange = onValueChange,
        focusRequester = focusRequester,
        enabled = isInputEnabled,
        onBlockedTap = if (enforceVoiceIme) {
            { showKeyboardDialog = true }
        } else {
            null
        }
    )

    if (enforceVoiceIme && showKeyboardDialog) {
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
